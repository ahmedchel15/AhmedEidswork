#########################################################################
#
# Name: ImportData_RosterStats.ps1
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
$Debug = $false
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

$dataFolder = "${customerFolder}\data\${servername}\rosterstats" 

if (-not (Test-Path $dataFolder)) {
	"ERROR: Folder does not exist: ${dataFolder}"
	"Probably not a Roster server"
	exit 1
}

$scriptName = "ImportData_RosterStats.ps1"
Write-Host "Script ${scriptName} started." -ForegroundColor "DarkGreen"
$scriptPath = split-path -Parent $MyInvocation.MyCommand.Definition
. "${scriptPath}\LoadFunctions.ps1"

#Logging
$logger = CreateLogger("Statistics")
$logobject = CreateLogObject($scriptname)

if ($fromDateString -eq "") { $fromDate = [datetime]::Today.AddDays(-1) } else { $fromDate = [datetime]::ParseExact($fromDateString, "yyyy-MM-dd", $null) }
if ($toDateString -eq "") { $toDate = [datetime]::Today.AddDays(-1) } else { $toDate = [datetime]::ParseExact($toDateString, "yyyy-MM-dd", $null) }
if ($fromDate -gt $toDate) { $fromDate = $toDate }

$databaseuri = "http://stats.intranet.plano:8086"
$databasename = "plano_stats"
$measurementname = "RosterStats"
$username = "plano_stats"
$password = "!!plano2020" | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $password)

for ($date = $fromDate; $date -le $toDate; $date = $date.AddDays(1)) {
	
	$dateString = $date.ToString("yyyy-MM-dd")

	$sourcefiles = Get-ChildItem -Path $dataFolder -Filter *_rosterstats_${datestring}.csv -File -recurse 
	Foreach ($sourcefile in $sourcefiles) {

		if ($sourcefile.length -ne 0) {
			$sourcefileFullName = $sourcefile.FullName
			Write-Host "${sourcefileFullName}" -ForegroundColor "Cyan"
					
			$InputObject = [Collections.Generic.List[pscustomobject]]::new()
			
			#Remove full stops from tag values
			$servername = $servername -replace '\.', '_'
			$customer = $customer -replace '\.', '_'

			Try {
							   
				$data = [IO.File]::ReadAllLines("$sourcefileFullName") | select-object -skip 1 						 
				$lines = $data.count
				$addToi = 1;
				$customer = $customerid				
					 							   
				for ($i = 0; $i -lt $lines; $i = $i + $addToi) {
					if ($lines -eq 1) {
						$line = $data.split(";")
					}
					else {
						
						$line = $data[$i].split(";")
					}
					
					$addToi = 1;
					$values = $line.split(";")
					
					try {
						#TimeStamp for metric
						$TimeStamp = [datetime]::ParseExact($values[2].replace('"', ''), "yyyyMMddHHmm", $null)
						#Metrics
						$SessionsValue = [convert]::ToDouble($values[3]) #$values[$MetricsHeaders["activesessions"])
						$PlannersValue = [convert]::ToDouble($values[4])
						$SchedulesValue = [convert]::ToDouble($values[5])
						$EmployeesValue = [convert]::ToDouble($values[6])
						$EmployeeDaysValue = [convert]::ToDouble($values[7])
						$LinksValue = [convert]::ToDouble($values[8])

						if ($values.Count -gt 9) {
							$UnconnectedSchedules = [convert]::ToDouble($values[9])
							$UnconnectedEmployees = [convert]::ToDouble($values[10])
							$UnconnectedEmployeeDays = [convert]::ToDouble($values[11])
							$UnconnectedLinks = [convert]::ToDouble($values[12])
							$PendingColumnValues = [convert]::ToDouble($values[13])
							$FreeWorkers = [convert]::ToDouble($values[14])
							
							$InputObject.Add([pscustomobject]@{
								PSTypeName = 'Metric'
								Measure	= $measurementname
								Metrics	= @{Sessions = $SessionsValue; Planners = $PlannersValue; Schedules = $SchedulesValue; Employees = $EmployeesValue; EmployeeDays = $EmployeeDaysValue; Links = $LinksValue; UnconnectedSchedules = $UnconnectedSchedules; UnconnectedEmployees = $UnconnectedEmployees; UnconnectedEmployeeDays = $UnconnectedEmployeeDays; UnconnectedLinks = $UnconnectedLinks; PendingColumnValues = $PendingColumnValues; FreeWorkers = $FreeWorkers }
								Tags	   = @{Customer = $customer; Server = $servername }
								TimeStamp  = $timestamp
							})
						}
						else {
							$InputObject.Add([pscustomobject]@{
								PSTypeName = 'Metric'
								Measure	= $measurementname
								Metrics	= @{Sessions = $SessionsValue; Planners = $PlannersValue; Schedules = $SchedulesValue; Employees = $EmployeesValue; EmployeeDays = $EmployeeDaysValue; Links = $LinksValue }
								Tags	   = @{Customer = $customer; Server = $servername }
								TimeStamp  = $timestamp
							})
						}
						
					
					}
					catch {
						$_.Exception.Message
						$content = "Fehler in Zeile " + $lineNumber + ";${line}"
						LogError("${content}")	
					}
					 
					$lineNumber++	
					if (0 -eq $lineNumber % $requestSize) {
						Try {
							$InputObjectArray = $InputObject.ToArray()
							$WriteInflux = $InputObjectArray | Write-Influx -Bulk -Database $databasename -Server $databaseuri -Credential $credential #-Verbose 
							$InputObject = [Collections.Generic.List[pscustomobject]]::new()
						}
						Catch {
							$InputObject = [Collections.Generic.List[pscustomobject]]::new()
							$_.Exception.Message
							$content = "Could not post to InfluxDB" + ";${sourcefileFullName}"
							LogError("${content}")	
						}
						
					}
					
				}
					
			}
			Catch {
				$_.Exception.Message
				$content = "Fehler in Zeile " + $lineNumber + ";${line}"
				LogError("${content}")	
						
			}	
					
			Try {
				$InputObjectArray = $InputObject.ToArray()
				$WriteInflux = $InputObjectArray | Write-Influx -Bulk -Database $databasename -Server $databaseuri -Credential $credential #-Verbose 
				$InputObject = [Collections.Generic.List[pscustomobject]]::new()
			}
			Catch {
				$InputObject = [Collections.Generic.List[pscustomobject]]::new()
				$_.Exception.Message
				$content = "Could not post to InfluxDB" + ";${sourcefileFullName}"
				LogError("${content}")	
			}	
							   
		}		
		else {
			$content = "file has a size of 0 bytes: ${sourcefileFullName}"
			#LogDebug("${content}")
		}
	} #foreach sourcefiles

	#DistinctPlanners
	$sourcefiles = Get-ChildItem -Path $dataFolder -Filter *_rosterstats_distinctplanners_${datestring}.csv -File -recurse
	Foreach ($sourcefile in $sourcefiles) {

		if ($sourcefile.length -ne 0) {
			$sourcefileFullName = $sourcefile.FullName
			Write-Host "${sourcefileFullName}" -ForegroundColor "Cyan"
					
			$InputObject = [Collections.Generic.List[pscustomobject]]::new()
			
			#Remove full stops from tag values
			$servername = $servername -replace '\.', '_'
			$customer = $customer -replace '\.', '_'

			Try {			   
				$data = [IO.File]::ReadAllLines("$sourcefileFullName") | select-object -skip 1 						 
				$lines = $data.count
				$addToi = 1;
				$customer = $customerid				
					 							   
				for ($i = 0; $i -lt $lines; $i = $i + $addToi) {
					if ($lines -eq 1) {
						$line = $data.split(";")
					}
					else {	
						$line = $data[$i].split(";")
					}
					
					$addToi = 1;
					$values = $line.split(";")

					try {
						#TimeStamp for metric
						$TimeStamp = [datetime]::ParseExact($values[2].replace('"', ''), "yyyyMMddHHmm", $null)
						#Metrics
						$DistinctPlanners = [convert]::ToDouble($values[3]) 

						$InputObject.Add([pscustomobject]@{
							PSTypeName = 'Metric'
							Measure	= $measurementname
							Metrics	= @{DistinctPlanners = $DistinctPlanners }
							Tags	   = @{Customer = $customer; Server = $servername }
							TimeStamp  = $timestamp
						})	
					}
					catch {
						$_.Exception.Message
						$content = "Fehler in Zeile " + $lineNumber + ";${line}"
						LogError("${content}")	
					}		
				}
			}
			Catch {
				$_.Exception.Message
				$content = "Fehler in Zeile " + $lineNumber + ";${line}"
				LogError("${content}")	
						
			}	
					
			Try {
				$InputObjectArray = $InputObject.ToArray()
				$WriteInflux = $InputObjectArray | Write-Influx -Bulk -Database $databasename -Server $databaseuri -Credential $credential #-Verbose 
				$InputObject = [Collections.Generic.List[pscustomobject]]::new()
			}
			Catch {
				$InputObject = [Collections.Generic.List[pscustomobject]]::new()
				$_.Exception.Message
				$content = "Could not post to InfluxDB" + ";${sourcefileFullName}"
				LogError("${content}")	
			}	
							   
		}		
		else {
			$content = "file has a size of 0 bytes: ${sourcefileFullName}"
			#LogDebug("${content}")
		}
	} #foreach sourcefiles
	
	##Weekly value only on monday
	if(($date).DayOfWeek.value__ -eq 1)
	{
		$distinctplannersperweek = 0 
		$distinctplannersObject = @()
			
		$fromDate2 = ($date).AddDays(-([int]($date).DayOfWeek)-7)
		$toDate2 = ($date).AddDays(-([int]($date).DayOfWeek))
		for ($date2 = $fromDate2; $date2 -le $toDate2; $date2 = $date2.AddDays(1)) {

			$dateString2 = $date2.ToString("yyyy-MM-dd")
			#DistinctPlannersList
			$sourcefiles = Get-ChildItem -Path $dataFolder -Filter *_rosterstats_distinctplannerslist_${datestring2}.csv -File -recurse
			Write-Host "${sourcefileFullName}" -ForegroundColor "Cyan"
			Foreach ($sourcefile in $sourcefiles) {	
					$sourcefileFullName = $sourcefile.FullName
					$data = Get-Content -LiteralPath "$sourcefileFullName"
					foreach($plannerinlist in $data)
					{
						$distinctplannersObject += ($plannerinlist)
					}
			}
		}
			
		$distinctplannersperweek = ($distinctplannersObject | Group-Object -NoElement | Select-Object -expand Name).Count

		try {
			#TimeStamp for metric, last monday
			$TimeStamp = $fromDate2
			#Metrics
			$DistinctPlanners = [convert]::ToDouble($values[3]) 

			$InputObject.Add([pscustomobject]@{
				PSTypeName = 'Metric'
				Measure	= $measurementname
				Metrics	= @{DistinctPlannersPerWeek = $distinctplannersperweek }
				Tags	   = @{Customer = $customer; Server = $servername }
				TimeStamp  = $timestamp
			})	
		}
		catch {
			$_.Exception.Message
			$content = "Fehler in Zeile " + $lineNumber + ";${line}"
			LogError("${content}")	
		}	
		
		Try {
			$InputObjectArray = $InputObject.ToArray()
			$WriteInflux = $InputObjectArray | Write-Influx -Bulk -Database $databasename -Server $databaseuri -Credential $credential #-Verbose 
			$InputObject = [Collections.Generic.List[pscustomobject]]::new()
		}
		Catch {
			$InputObject = [Collections.Generic.List[pscustomobject]]::new()
			$_.Exception.Message
			$content = "Could not post to InfluxDB" + ";${sourcefileFullName}"
			LogError("${content}")	
		}	

	}#Weekly value
	
} #for($date)


