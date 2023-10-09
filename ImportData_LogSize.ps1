# Name: ImportData_LogSize.ps1
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

$scriptName = "ImportData_LogSize.ps1"
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
$measurementname = "LogSize"
$username = "plano_stats"
$password = "!!plano2020" | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $password)


$InputObject = [Collections.Generic.List[pscustomobject]]::new()
$lineNumber = 0

for ($date = $fromDate; $date -le $toDate; $date = $date.AddDays(1)) {
    $dateString = $date.ToString("yyyy-MM-dd")
    $timestamp = $date.ToUniversalTime()

    $sourcefiles = Get-ChildItem -Path $planolog -Filter *_LogSize_${datestring}.csv -File -Recurse

    foreach ($sourcefile in $sourcefiles) {
       if ($sourcefile.Length -ne 0) {
        $sourcefileFullName = $sourcefile.FullName
        Write-Host "${sourcefileFullName}" -ForegroundColor "Cyan"

        try {   
             $content = Get-Content -Path $sourcefile.FullName -Raw
             $logData = ConvertFrom-Csv -InputObject $content -Delimiter ";"
    
    foreach ($entry in $logData) {
        
        try{
            [double] $LogPlano = ($entry.Planolog_ActualSize)
            [double]$LogInterflex = ($entry.Interflexlog_ActualSize)
            [double]$LogXimes = ($entry.Ximeslog_ActualSize)
            [double]$LogTotal = ($entry.TheTotalsize)
            
            $InputObject.Add([PSCustomObject]@{
                PSTypeName = 'Metric'
                Measure = $measurementname
                Metrics = @{
                    LogTotal = $LogTotal
                    LogPlano = $LogPlano
                    LogInterflex = $LogInterflex
                    LogXimes = $LogXimes
                }
                Tags = @{Customer =[string]$customerid; Server=[string]$servername; }  
                TimeStamp = $timestamp
            })

            [double]$LogPlanoY = ($entry.Planolog_YesterdaySize)
            [double]$LogInterflexY = ($entry.Interflexlog_YesterdaySize)
            [double]$LogXimesY = ($entry.Ximeslog_YesterdaySize)
            [double]$LogTotalY = ($entry.TotalSize_FromYesterday)
            
            $InputObject.Add([PSCustomObject]@{
                PSTypeName = 'Metric'
                Measure = $measurementname
                Metrics = @{
                    LogTotal = $LogTotalY
                    LogPlano = $LogPlanoY
                    LogInterflex = $LogInterflexY
                    LogXimes = $LogXimesY
                }
                Tags = @{Customer =[string]$customerid; Server=[string]$servername; }  
                TimeStamp = $timestamp.AddDays(-1)
            })
    }
      
      catch {
             $errorMessage = $_.Exception.Message
             $content = "Error getting LogSize info from ${sourcefileFullName}: $errorMessage"
             LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};${content}")
        }

        $lineNumber++
        } 
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