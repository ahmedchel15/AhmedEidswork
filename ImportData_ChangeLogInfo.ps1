#########################################################################
#
# Name: ImportData_ChangeLogInfo.ps1
#
# Version: 1.0.0
#
# Description: 
#
#########################################################################

#Requires -Version 7

param(
	[string]$customerFolder,
	[string]$servername,
	[string]$customerid,
	[string]$fromDateString,
	[string]$toDateString
)

#########################################################################
#Activate debug output ($true / $false)
$Debug = $true
#########################################################################

#Parameter for splitting Write-Influx requests
$requestSize = 5000

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

$dataFolder = "${customerFolder}\logs\${servername}\changelog" 

if (-not (Test-Path $dataFolder)) {
	#"warn: Folder does not exist: ${dataFolder}"
	exit 1
}

$scriptName = "ImportData_ChangeLogInfo.ps1"
Write-Host "Script ${scriptName} started." -ForegroundColor "DarkGreen"
$scriptPath = split-path -Parent $MyInvocation.MyCommand.Definition
. "${scriptPath}\LoadFunctions.ps1"

#Logging
$logger = CreateLogger("Statistics")
$perflogger = CreateLogger("StatsPerformance")
$logobject = CreateLogObject($scriptname)

if ($fromDateString -eq "") { $fromDate = [datetime]::Today.AddDays(-1)} else { $fromDate = [datetime]::ParseExact($fromDateString, "yyyy-MM-dd", $null) }
if ($toDateString -eq "") { $toDate = [datetime]::Today.AddDays(-1) } else { $toDate = [datetime]::ParseExact($toDateString, "yyyy-MM-dd", $null) }
if ($fromDate -gt $toDate) { $fromDate = $toDate }


$databaseuri = "http://stats.intranet.plano:8086"
$databasename = "plano_stats_uploads"
$measurementname = "ChangeLogInfo"
$username = "plano_stats"
$password = "!!plano2020" | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username,$password)

#########################################################################
# Statistics API for grafana
# Key eyJrIjoiME03WHRIVHV0VHJPUUZzTmRtTDNxN3NZR05Sck5MUk8iLCJuIjoiU3RhdHMiLCJpZCI6MX0=
$grafanaToken = 'eyJrIjoiME03WHRIVHV0VHJPUUZzTmRtTDNxN3NZR05Sck5MUk8iLCJuIjoiU3RhdHMiLCJpZCI6MX0='
$grafanaUri = 'https://stats.intranet.plano'
# Configure here: https://stats.intranet.plano/org/apikeys
#########################################################################

$InputObject = [Collections.Generic.List[pscustomobject]]::new()

$sourcefiles = Get-ChildItem -Path $dataFolder -Filter *.txt -File -recurse | Where-Object { $_.LastWriteTime -gt $fromDate.AddDays(-120) }
Foreach ($sourcefile in $sourcefiles) {

	if ($sourcefile.length -ne 0)
	{
		$sourcefileFullName = $sourcefile.FullName
		Write-Host "${sourcefileFullName}" -ForegroundColor "Cyan"
		
		if ($sourcefileFullName -match ".*\\([0-9]{8})(.*).txt")
			{
				if ($sourcefileFullName -match ".*\\([0-9]{8}_[0-9]{4})(.*).txt")
				{
					$customerChangeLogDate = [datetime]::ParseExact($matches[1].replace('"',''), "yyyyMMdd_HHmm", $null)
				}
				elseif ($sourcefileFullName -match ".*\\([0-9]{8}_[0-9]{2})(.*).txt")
				{
					$customerChangeLogDate = [datetime]::ParseExact($matches[1].replace('"',''), "yyyyMMdd_HH", $null)
				}
				elseif ($sourcefileFullName -match ".*\\([0-9]{12})(.*).txt")
				{
					$customerChangeLogDate = [datetime]::ParseExact($matches[1].replace('"',''), "yyyyMMddHHmm", $null)
				}	
				elseif($sourcefileFullName -match ".*\\([0-9]{10})(.*).txt")
				{
					$customerChangeLogDate = [datetime]::ParseExact($matches[1].replace('"',''), "yyyyMMddHH", $null)
				}
				elseif ($sourcefileFullName -match ".*\\([0-9]{8})(.*).txt")
				{
					$customerChangeLogDate = [datetime]::ParseExact($matches[1].replace('"',''), "yyyyMMdd", $null)
				}
				$customerChangeLogName = $matches[2].Trim()
				$customerChangeLogDateString = $customerChangeLogDate.ToString().Substring(0,10)
				
				$customerChangeLogName = ReplaceBadCharactersForInflux($customerChangeLogName)			
				
				if($Debug -eq $true){	
					$customerChangeLogDate
					$customerChangeLogDateString
					$customerChangeLogName
				}
				
				try{
					$InputObject.Add([pscustomobject]@{
						PSTypeName = 'Metric'
						Measure    = $measurementname
						Metrics    = @{customerChangeLogName=$customerChangeLogName;customerChangeLogDate=$customerChangeLogDateString;Server=$servername}
						Tags       = @{Customer=$customerid;Server=$servername}
						TimeStamp  = $customerChangeLogDate
					})
								
				}
				catch {
					$content = "Fehler in Zeile " + $lineNumber + ";${line}"
					LogError("${content}")	
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
				}
			
			else{
				$content = "source filename didn't match: ${sourcefileFullName}"
				LogWarn("${content}"	
				break #exit 1
			}

		}	
		else {
            $sourcefileFullName = $sourcefile.FullName
            $content = "file has a size of 0 bytes: ${sourcefileFullName}"
            #LogDebug("${content}")	
		} 
} #foreach sourcefiles

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
