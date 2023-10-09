#########################################################################
#
# Name: ImportData_EmployeesLicensed.ps1
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

$dataFolder = "${customerFolder}\logs\${servername}\serverinfo" 

if (-not (Test-Path $dataFolder)) {
	#"warn: Folder does not exist: ${dataFolder}"
	exit 1
}

$scriptName = "ImportData_EmployeesLicensed.ps1"
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
$measurementname = "EmployeeLicensedStats"
$username = "plano_stats"
$password = "!!plano2020" | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username,$password)

for($date = $fromDate; $date -le $toDate; $date = $date.AddDays(1)) {
	
	$dateString = $date.ToString("yyyy-MM-dd")
    $timestamp = $date.ToUniversalTime() #[datetime]::ParseExact($values[3].replace('"',''), "yyyy-MM-dd", $null)

	$sourcefiles = Get-ChildItem -Path $dataFolder -Filter *_licensedemployees_${datestring}.log -File -recurse 
	Foreach ($sourcefile in $sourcefiles) {

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
					
					#allemployees;licensedemployees;miniumlicense;maximumlicense
					[int]$allemployees = $values[0]
					[int]$licensedemployees = $values[1]
					[int]$miniumlicense = $values[2]
					[int]$maximumlicense = $values[3]	
					
					$InputObject.Add([pscustomobject]@{
									PSTypeName = 'Metric'
									Measure    = $measurementname
									Metrics    = @{AllEmployees = $allemployees ;LicensedEmployees = $licensedemployees; MiniumLicense = $miniumlicense; MaximumLicense = $maximumlicense}
									Tags       = @{Customer=$customer;Servername=$servername}
									TimeStamp  = $timestamp
								})
								
					$lineNumber++	
					if (0 -eq $lineNumber % $requestSize) {
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
						
				}
			}
			catch{
				$_.Exception.Message
                $content = "Fehler in Zeile " + $lineNumber + ";${line}"
                LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};${content}")
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