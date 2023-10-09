# Name: ImportData_RosterTasksStats.ps1
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

$scriptName = "ImportData_RosterTasksStats.ps1"
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
$measurementname = "RosterTasksStats"
$username = "plano_stats"
$password = "!!plano2020" | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $password)


$InputObject = [Collections.Generic.List[pscustomobject]]::new()
$InputObjectdistinct = [Collections.Generic.List[pscustomobject]]::new()
$lineNumber = 0

for ($date = $fromDate; $date -le $toDate; $date = $date.AddDays(1)) {
    $dateString = $date.ToString("yyyy-MM-dd")
    $timestamp = $date.ToUniversalTime()

    $sourcefiles = Get-ChildItem -Path "C:\plano\statsreporting" -Filter *taskdata.csv -File -Recurse
    $sourcefilesdistinct= Get-ChildItem -Path "C:\plano\statsreporting" -Filter *distincttask_data.csv -File -Recurse

    foreach ($sourcefile in $sourcefiles){
        if ($sourcefile.Length -ne 0){
         $sourcefileFullName = $sourcefile.FullName
         Write-Host "${sourcefileFullName}" -ForegroundColor "Cyan"
 
         try{
              $content = Get-Content -Path $sourcefile.FullName -Raw
              $logData = ConvertFrom-Csv -InputObject $content -Delimiter ","

     foreach ($entry in $logData) {
        try{
            $InputObject.Add([PSCustomObject]@{
                PSTypeName = 'Metric'
                Measure = $measurementname
                Metrics = @{
                    
                      
                    TaskName   =$entry.TaskName
                    Type       =$entry.Type
                    Completed  =$entry.Completed
                    Running    =$entry.Running
                    TotalTasks =$entry.TotalTasks

                }
                Tags = @{Customer =[string]$customerid; Server=[string]$servername;date       =$entry.dateinterval ;TaskId     =$entry.TaskId ; }  
                TimeStamp = $timestamp
                
                
            })


        }
        catch {
               $errorMessage = $_.Exception.Message
               $content = "Error getting RosterTasksStats info from ${sourcefileFullName}: $errorMessage"
               LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};${content}")
"2"
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
            }  catch {
                $errorMessage = $_.Exception.Message
                $content = "Error in ${sourcefileFullName}: $errorMessage"
                LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};${content}")
              }

            } else {
                    $sourcefileFullName = $sourcefile.FullName
                    $content = "File has a size of 0 bytes: ${sourcefileFullName}"  
              } 
            }
        
            foreach ($sourcefiledistinct in $sourcefilesdistinct){ 
                if ($sourcefiledistinct.Length -ne 0) {
                    $sourcefiledistinctFullName = $sourcefiledistinct.FullName
                    Write-Host "${sourcefiledistinctFullName}" -ForegroundColor "Cyan"
             
                    try{    
                        $contentdistinct = Get-Content -Path $sourcefiledistinct.FullName -Raw
                        $logDatadistinct = ConvertFrom-Csv -InputObject $contentdistinct -Delimiter "," 
            
                        foreach ($entrydistinct in $logDatadistinct) {
                            try{
								$entrydistinct.TaskName
								$entrydistinct.Running
								$entrydistinct.TotalTasks
								$entrydistinct.Date
								$timestamp
                                $InputObjectdistinct.Add([PSCustomObject]@{
                                    PSTypeName = 'Metric'
                                    Measure = 'Roster_distinctTaskstats'
                                    Metrics = @{
                                        
                                         
                                        TaskName   =$entrydistinct.TaskName
                                        Type       =$entrydistinct.Type
                                        Completed  =$entrydistinct.Completed
                                        Running    =$entrydistinct.Running
                                        TotalTasks =$entrydistinct.TotalTasks
                                    }
                                    Tags = @{Customer =[string]$customerid; Server=[string]$servername;date       =$entrydistinct.Date ; TaskId =$entrydistinct.TaskId;}  
                                    TimeStamp = $timestamp
                                    
                        })
            
            
                    }
                  catch {
                    $errorMessage = $_.Exception.Message
                    $contentdistinct = "Error getting RosterTasksStats info from ${sourcefiledistinctFullName}: $errorMessage"
                    LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};$contentdistinct")
               }
               $lineNumber++
            }
            if (0 -eq $lineNumber % $requestSize){
                Try{    						
                    $InputObjectdistinctArray = $InputObjectdistinct.ToArray()
                    $InputObjectdistinctArray.Count
                    $WriteInflux = $InputObjectdistinctArray | Write-Influx -Bulk -Database $databasename -Server $databaseuri -Credential $credential #-Verbose 
                    $InputObjectdistinct = [Collections.Generic.List[pscustomobject]]::new()
                }
            Catch{    	
                    $InputObjectdistinct = [Collections.Generic.List[pscustomobject]]::new()
                    $_.Exception.Message
                    $contentdistinct = "Could not post to InfluxDB" + ";${sourcefiledistinctFullName}"
                    LogError("${contentdistinct}")
                    	
                }   
            }
        } catch {
            $errorMessage = $_.Exception.Message
            $contentdistinct = "Error in ${sourcefiledistinctFullName}: $errorMessage"
            LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};${contentdistinct}")
              }
        } else{
            $sourcefiledistinctFullName = $sourcefiledistinct.FullName
            $contentdistinct = "File has a size of 0 bytes: ${sourcefiledistinctFullName}"
                }
            }
        }
		
		
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
		
Try{                            
	$InputObjectdistinctArray = $InputObjectdistinct.ToArray()
	$InputObjectdistinctArray.Count
	$WriteInflux = $InputObjectdistinctArray | Write-Influx -Bulk -Database $databasename -Server $databaseuri -Credential $credential #-Verbose 
	$InputObjectdistinct = [Collections.Generic.List[pscustomobject]]::new()
}
Catch{      
		$InputObjectdistinct = [Collections.Generic.List[pscustomobject]]::new()
		$_.Exception.Message
		$contentdistinct = "Could not post to InfluxDB" + ";${sourcefiledistinctFullName}"
		LogError("${contentdistinct}")
			
	}