#########################################################################
#
# Name: ImportData_UploadStats.ps1
#
# Version: 1.0.0
#
# Description: 
#
#########################################################################

#Requires -Version 7

param(
	[string]$fromDateString,
	[string]$toDateString
)

#Parameter for splitting Write-Influx requests
$requestSize = 5000

$dataFolder = "C:\plano\Logs" 

$scriptName = "ImportData_UploadStats.ps1"
Write-Host "Script ${scriptName} started." -ForegroundColor "DarkGreen"
$scriptPath = split-path -Parent $MyInvocation.MyCommand.Definition
. "${scriptPath}\LoadFunctions.ps1"

#Logging
$logger = CreateLogger("Statistics")
$logobject = CreateLogObject($scriptname)

LogInfo("Processing started.")

$databaseuri = "http://stats.intranet.plano:8086"
$databasename = "plano_stats_uploads"
$measurementname = "UploadStats"
$username = "plano_stats"
$password = "!!plano2020" | ConvertTo-SecureString -asPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $password)

if ($fromDateString -eq "") { $fromDate = [datetime]::Today.AddDays(-1) } else { $fromDate = [datetime]::ParseExact($fromDateString, "yyyy-MM-dd", $null) }
if ($toDateString -eq "") { $toDate = [datetime]::Today.AddDays(-1) } else { $toDate = [datetime]::ParseExact($toDateString, "yyyy-MM-dd", $null) }
if ($fromDate -gt $toDate) { $fromDate = $toDate }

$InputObject = [Collections.Generic.List[pscustomobject]]::new()

for ($date = $fromDate; $date -le $toDate; $date = $date.AddDays(1)) {
	$dateString = $date.ToString("yyyy-MM-dd")
	   
	$sourcefiles = Get-ChildItem -Path $dataFolder -Filter DistributedCustomerServersTotal.log -File
	Foreach ($sourcefile in $sourcefiles) {

		if ($sourcefile.length -ne 0) {
			$sourcefileFullName = $sourcefile.FullName

			Try {
				$dataAll = [IO.File]::ReadAllLines("$sourcefileFullName")
				$data = ($dataAll | Where-Object { $_.split(";")[3] -eq "${datestring}" })							 
				$lines = $data.count
				$addToi = 1;
								
				for ($i = 0; $i -lt $lines; $i = $i + $addToi) {
					if ($lines -eq 1) {
						# if really only one resulting (Call|Return)-line is existing, then use $data as $line
						# otherwise the split would be done on a single character, which leads to an error 
						$line = $data.split(";")
					}
					else {
						
						$line = $data[$i].split(";")
					}
					
					$addToi = 1;
					$values = $line.split(";")

					$date = [datetime]::ParseExact($values[3].replace('"', ''), "yyyy-MM-dd", $null)
					$datestring = ($date).tostring("yyyy-MM-dd")
					$customer = $values[1].replace('"', '')
					$servername = $values[2].replace('"', '')
					
					#Remove full stops from tag values
					$servername = $servername -replace '\.', '_'
					$customer = $customer -replace '\.', '_'
					
					
					try {
							$LogTotalSizeValue = [convert]::ToDouble($values[4].replace('"', ''))
							
							$InputObject.Add([pscustomobject]@{
								PSTypeName = 'Metric'
								Measure	= $measurementname
								Metrics	= @{LogTotalSize = $LogTotalSizeValue}
								Tags	   = @{Customer=$customer;Server=$servername}
								TimeStamp  = $date
							})					 
					}
					catch {
						$_.Exception.Message
						$content = "Fehler in Zeile " + $lineNumber + ";${line}"
						LogError("${content}")	
					}
					$lineNumber++	
						
					if (0 -eq $lineNumber % $requestSize){
						Try {#split request
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
			}
			Catch {
				$_.Exception.Message
				$content = "Fehler in Zeile " + $lineNumber + ";${line}"
				LogError("${content}")			
			}
		
		}	
		else {
			$sourcefileFullName = $sourcefile.FullName
			$content = "file contains no content. Probably DistributedCustomerServersTotal not correct set up. ${sourcefileFullName}"	
			LogWarn("${content}")	
		}
	} #foreach sourcefiles
} # foreach date

Try {#final request
	$InputObjectArray = $InputObject.ToArray()
	$WriteInflux = $InputObjectArray | Write-Influx -Bulk -Database $databasename -Server $databaseuri -Credential $credential #-Verbose 
	$InputObject = [Collections.Generic.List[pscustomobject]]::new()
}
Catch{
	$InputObject = [Collections.Generic.List[pscustomobject]]::new()
	$_.Exception.Message
	$content = "Could not post to InfluxDB" + ";${sourcefileFullName}"
	LogError("${content}")	
}#final request end	

LogInfo("Processed successfully.")