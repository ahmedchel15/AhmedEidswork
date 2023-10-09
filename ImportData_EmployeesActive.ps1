#########################################################################
#
# Name: ImportData_EmployeesActive.ps1
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

$dataFolder = "${customerFolder}\logs\${servername}\metrics" 

if (-not (Test-Path $dataFolder)) {
	#"warn: Folder does not exist: ${dataFolder}"
	exit 1
}

$scriptName = "ImportData_EmployeesActive.ps1"
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

#database connection info
$databaseuri = "http://stats.intranet.plano:8086"
$databasename = "plano_stats_uploads"
$measurementname = "EmployeeActiveStats"
$username = "plano_stats"
$password = "!!plano2020" | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username,$password)

$comparisanDate = Get-Date

for($date = $fromDate; $date -le $toDate; $date = $date.AddDays(1)) {
	
	$dateString = $date.ToString("yyyy-MM-dd")
    $timestamp = $date.ToUniversalTime() #[datetime]::ParseExact($values[3].replace('"',''), "yyyy-MM-dd", $null)

	$sourcefiles = Get-ChildItem -Path $dataFolder -Filter *_employeesactive_${datestring}.csv -File -recurse 
	Foreach ($sourcefile in $sourcefiles) {
		
		[int]$totalEmployees = 0
		[int]$activeEmployees = 0
		[int]$leftEmployees = 0
		[int]$futureEmployees = 0
		
		[int]$leftEmployeesLast1Quarter = 0
		[int]$leftEmployeesLast2Quarter = 0
		[int]$leftEmployeesLast3Quarter = 0
		
		[int]$leftEmployeesLast1Year = 0
		[int]$leftEmployeesLast2Year = 0
		[int]$leftEmployeesLast3Year = 0
		

		if ($sourcefile.length -ne 0)
		{
			$sourcefileFullName = $sourcefile.FullName
            Write-Host "${sourcefileFullName}" -ForegroundColor "Cyan"
			
			$InputObject = [Collections.Generic.List[pscustomobject]]::new()

            Try {
                $data = [IO.File]::ReadAllLines("$sourcefileFullName") | select-object -skip 1 						 
                $lines = $data.count
                
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
					
					#Eintag;Austag
					try{
						$eintagDate = [datetime]::ParseExact($values[0].replace('"',''), "yyyy-MM-dd", $null)
						$austagDate = [datetime]::ParseExact($values[1].replace('"',''), "yyyy-MM-dd", $null)
						
						#Allways count an employee
						$totalEmployees++
						
						if($comparisanDate -ge $eintagDate -and $comparisanDate -lt $austagDate){
							$activeEmployees++
						}
						elseif($eintagDate -gt $comparisanDate -and $comparisanDate -lt $austagDate) {
							$futureEmployees++
						}
						else{
							$leftEmployees++
							
							if($comparisanDate -gt $austagDate.AddDays(-270)){
								$leftEmployeesLast3Quarter++
							}
							elseif($comparisanDate -gt $austagDate.AddDays(-180)){
								$leftEmployeesLast2Quarter++
							}
							elseif($comparisanDate -gt $austagDate.AddDays(-90)){
								$leftEmployeesLast1Quarter++
							}
							else{
								LogWarn("Missing some date in Employees left last quarters. Eintag: ${eintagDate}. Austag: ${austagDate}.")
							}
							
							if($comparisanDate -gt $austagDate.AddDays(-365*3)){
								$leftEmployeesLast3Quarter++
							}
							elseif($comparisanDate -gt $austagDate.AddDays(-365*2)){
								$leftEmployeesLast2Quarter++
							}
							elseif($comparisanDate -gt $austagDate.AddDays(-365)){
								$leftEmployeesLast1Quarter++
							}
							else{
								LogWarn("Missing some date in Employees left last years. Eintag: ${eintagDate}. Austag: ${austagDate}.")
							}
							
						}
					}
					catch{
						$_.Exception.Message
						$content = "Error converting / comparing days" + ";${sourcefileFullName}"
						LogError("${content}")	
					}	
		
					$lineNumber++				
				}
				
				$InputObject.Add([pscustomobject]@{
								PSTypeName = 'Metric'
								Measure    = $measurementname
								Metrics    = @{TotalEmployees = $totalEmployees ; ActiveEmployees = $activeEmployees; FutureEmployees = $futureEmployees; LeftEmployeesLast1Quarter = $leftEmployeesLast1Quarter; LeftEmployeesLast2Quarter = $leftEmployeesLast2Quarter; LeftEmployeesLast3Quarter = $leftEmployeesLast3Quarter; LeftEmployeesLast1Year = $leftEmployeesLast1Year; LeftEmployeesLast2Year = $leftEmployeesLast2Year; LeftEmployeesLast3Year = $leftEmployeesLast3Year}
								Tags       = @{Customer=$customer;Servername=$servername}
								TimeStamp  = $timestamp
							})
							
			}
			catch{
				$_.Exception.Message
                $content = "Fehler in Zeile " + $lineNumber + ";${line}"
                LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};${content}")
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
				LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};${content}")	
			}

		}
			
		else {
            $sourcefileFullName = $sourcefile.FullName
            $content = "file has a size of 0 bytes: ${sourcefileFullName}"
            #LogDebug("${content}")	
		} 
	} #foreach sourcefiles

} #for($date)