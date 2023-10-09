# Name: ImportData_OSInformation.ps1
# Version: 1.0.0
# Description:

# Requires -Version 7

param(
    [string]$customerFolder,
    [string]$servername,
    [string]$customerid,
    [string]$fromDateString,
    [string]$toDateString
)

$Debug = $false

$requestSize = 8000

if ($customerFolder -eq "") {
    "No customerFolder set. Please use parameter -customerFolder ""<customerFolder>"""
    exit 1
}
if ($customerid -eq "") {
    "No customerid set. Please use parameter -customerid ""<CUSTOMER>"""
    exit 1
}
if ($servername -eq "") {
    "No servername set. Please use parameter -servername ""<SERVERNAME>"""
    exit 1
}

$dataFolder = "${customerFolder}\logs\${servername}\serverinfo"

if (-not (Test-Path $dataFolder)) {
    exit 1
}

$scriptName = "ImportData_OSInformation.ps1"
Write-Host "Script ${scriptName} started." -ForegroundColor "DarkGreen"
$scriptPath = split-path -Parent $MyInvocation.MyCommand.Definition
. "${scriptPath}\LoadFunctions.ps1"

$logger = CreateLogger("Statistics")
$perflogger = CreateLogger("StatsPerformance")
$logobject = CreateLogObject($scriptname)

if ($fromDateString -eq "") { $fromDate = [datetime]::Today.AddDays(-1)} else { $fromDate = [datetime]::ParseExact($fromDateString, "yyyy-MM-dd", $null) }
if ($toDateString -eq "") { $toDate = [datetime]::Today.AddDays(-1) } else { $toDate = [datetime]::ParseExact($toDateString, "yyyy-MM-dd", $null) }
if ($fromDate -gt $toDate) { $fromDate = $toDate }

$databaseuri = "http://stats.intranet.plano:8086"
$databasename = "plano_stats_uploads"
$measurementname = "OSInformation"
$username = "plano_stats"
$password = "!!plano2020" | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username,$password)

$InputObject = [Collections.Generic.List[pscustomobject]]::new()

for ($date = $fromDate; $date -le $toDate; $date = $date.AddDays(1)) {
    $dateString = $date.ToString("yyyy-MM-dd")
    $timestamp = $date.ToUniversalTime()

    $sourcefiles = Get-ChildItem -Path $dataFolder -Filter *_serverinfo_${datestring}.log -File -recurse
    
    foreach ($sourcefile in $sourcefiles) {
        if ($sourcefile.Length -ne 0) {
            $sourcefileFullName = $sourcefile.FullName
            Write-Host "${sourcefileFullName}" -ForegroundColor "Cyan"
    
            try {
                $content = Get-Content -Path $sourcefileFullName -Raw
                $jsonContent = $content -replace "(?<=\})\s*,\s*", ","
                $data = $jsonContent | ConvertFrom-Json
    
                $OSVersion = $data.OsVersion
                $OsUptimeInDays = $data.OsUptime.TotalDays
                $WindowsProductName = $data.OsName
				
				if($Debug -eq $true){
					"=== Hotfix Count ==="
					$data.OsHotFixes.Count
				}
				
                foreach ($Hotfix in $data.OsHotFixes) {
                    
					try{
						$installedOnDate = [DateTime]::ParseExact($Hotfix.InstalledOn, "M/d/yyyy", $null)
						$formattedInstalledOn = $installedOnDate.ToString("yyyy-MM-dd")
						$HotfixDescription = $Hotfix.Description
						
						if($Debug -eq $true){
							"=== Hotfix Info ==="
							"Timestamp:            ${timeStamp}"
							"WindowsProductName:   ${WindowsProductName}"
							"OS Version:           ${$OSVersion}"
							"HotfixDescription:    ${HotfixDescription}"
						}
						
						$InputObject.Add([PSCustomObject]@{
							PSTypeName = 'Metric'
							Measure    = $measurementname
							Metrics    = @{
								WindowsProductName = $data.OsName
								OSVersion         = $OSVersion
								OsBuildNumber     = $data.OsBuildNumber
								InstalledOn       = $formattedInstalledOn
								OsUptimeInDays    = $OsUptimeInDays
								Description       = $Hotfix.Description
							}
							Tags       = @{Customer=[string]$customerid; Server=[string]$servername; HotFixID = $Hotfix.HotFixID}
							TimeStamp  = $timestamp
						})
					}
					catch {
						$errorMessage = $_.Exception.Message
						$content = "Error getting hotfix info from ${sourcefileFullName}: $errorMessage"
						LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};${content}")
					}
                    
                }

				$lineNumber++	
				if (0 -eq $lineNumber % $requestSize){
					Try {
						$InputObjectArray = $InputObject.ToArray()
						$WriteInflux = $InputObjectArray | Write-Influx -Bulk -Database $databasename -Server $databaseuri -Credential $credential #-Verbose 
						$InputObject = [Collections.Generic.List[pscustomobject]]::new()
					}
					Catch{
						$InputObject = [Collections.Generic.List[pscustomobject]]::new()
						$_.Exception.Message
						$content = "Could not post to InfluxDB" + ";${sourcefileFullName}"
						LogError("${content}")	
					}
					
				}
    
            } catch {
                $errorMessage = $_.Exception.Message
                $content = "Error in ${sourcefileFullName}: $errorMessage"
                LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};${content}")
            }
        } else {
            $sourcefileFullName = $sourcefile.FullName
            $content = "File has a size of 0 bytes: ${sourcefileFullName}"
            # LogDebug("${content}")
        }
    }
}

Try {
	$InputObjectArray = $InputObject.ToArray()
	if($InputObjectArray.Count -gt 0){
		$WriteInflux = $InputObjectArray | Write-Influx -Bulk -Database $databasename -Server $databaseuri -Credential $credential #-Verbose 
	}
	$InputObject = [Collections.Generic.List[pscustomobject]]::new()
	}
Catch{
	$InputObject = [Collections.Generic.List[pscustomobject]]::new()
	$_.Exception.Message
	$content = "Could not post to InfluxDB" + ";${sourcefileFullName}"
	LogError("${content}")	
}