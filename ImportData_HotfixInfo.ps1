#########################################################################
#
# Name: ImportData_HotfixInfo.ps1
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

$dataFolder = "${customerFolder}\logs\${servername}\hotfixes" 

if (-not (Test-Path $dataFolder)) {
	#"warn: Folder does not exist: ${dataFolder}"
	exit 1
}

$scriptName = "ImportData_HotfixInfo.ps1"
Write-Host "Script ${scriptName} started." -ForegroundColor "DarkGreen"
$scriptPath = split-path -Parent $MyInvocation.MyCommand.Definition
. "${scriptPath}\LoadFunctions.ps1"

#Logging
$logger = CreateLogger("Statistics")
$logobject = CreateLogObject($scriptname)

if ($fromDateString -eq "") { $fromDate = [datetime]::Today.AddDays(-1)} else { $fromDate = [datetime]::ParseExact($fromDateString, "yyyy-MM-dd", $null) }
if ($toDateString -eq "") { $toDate = [datetime]::Today.AddDays(-1) } else { $toDate = [datetime]::ParseExact($toDateString, "yyyy-MM-dd", $null) }
if ($fromDate -gt $toDate) { $fromDate = $toDate }

$databaseuri = "http://stats.intranet.plano:8086"
$databasename = "plano_stats_uploads"
$measurementname = "HotfixInfo"
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

<# $headers = @{
    Authorization="Bearer ${grafanaToken}"
    Content='application/json'
}
$grafanaAPIAnnotation = $grafanaUri + "/api/annotations"
$contentExample = "{
  "dashboardUID":"jcIIG-07z",
  "panelId":1,
  "time":1507037197339,
  "timeEnd":1507180805056,
  "tags":["tag1","tag2"],
  "text":"Annotation Description"
}"
$responseData = (Invoke-RestMethod -Method Post -Uri $grafanaAPIAnnotation -Headers $headers -Content)

 #>

$InputObject = [Collections.Generic.List[pscustomobject]]::new()

# Customername from CustomerData
try{
	$CustomerIdConfig = GetConfigValue "CustomerData"
	$CustomerIDCurrentCustomer = $customerid

	$CustomerIDPosition = [array]::IndexOf($CustomerIdConfig.Id, $CustomerIDCurrentCustomer)
	$ProcessServers = $CustomerIdConfig[$CustomerIDPosition]
	$CustomernameForImport = $ProcessServers.Name
}
catch{
	$_.Exception.Message
	$content = "Error retrieving customer name from CustomerData: " + $_.Exception.Message
	LogError("${content}")	
}

if($CustomernameForImport -eq "" -or $null -eq $CustomernameForImport){
	$CustomernameForImport = "N/A"
}
# Customername from CustomerData

$sourcefiles = Get-ChildItem -Path $dataFolder -Filter *.txt -File -recurse | Where-Object { $_.LastWriteTime -gt $fromDate.AddDays(-120) }
Foreach ($sourcefile in $sourcefiles) {

	if ($sourcefile.length -ne 0)
	{
		$sourcefileFullName = $sourcefile.FullName
		Write-Host "${sourcefileFullName}" -ForegroundColor "Cyan"
		
		if ($sourcefileFullName -match ".*\\([0-9]{8})(.*).txt")
			{
				$customerHotfixDate = [datetime]::ParseExact($matches[1].replace('"',''), "yyyyMMdd", $null)
				$customerHotfixName = $matches[2].Trim()
				$customerHotfixDateString = $customerHotfixDate.ToString("yyyy.MM.dd")
				$customerHotfixInstallDateString = $sourcefile.LastWriteTime.ToString("yyyy.MM.dd HH:mm:ss")
				$customerHotfixTimeToFix = (New-TimeSpan -Start $customerHotfixDate -End ($sourcefile.LastWriteTime)).Days
				[double]$customerHotfixTimeToFixDouble = [Math]::Round($customerHotfixTimeToFix,2)
				
				$customerHotfixName = ReplaceBadCharactersForInflux($customerHotfixName)
				
				if($Debug -eq $true){	
					$customerHotfixDate
					$customerHotfixName
				}
				
				try{
					$InputObject.Add([pscustomobject]@{
						PSTypeName = 'Metric'
						Measure    = $measurementname
						Metrics    = @{Customername=$CustomernameForImport;CustomerHotfixName=$customerHotfixName;CustomerHotfixInstallationDate=$customerHotfixInstallDateString;CustomerHotfixDate=$customerHotfixDateString;Server=$servername;TimeToInstall=$customerHotfixTimeToFixDouble}
						Tags       = @{Customer=$customerid;Server=$servername}
						TimeStamp  = $customerHotfixDate
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
							$exceptionmessage = $_.Exception.Message
							$content = "Could not post to InfluxDB" + ";${sourcefileFullName};"
							LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};${content}")
							LogError("${exceptionmessage}")
						}
						
					}
				}
			
			else{
				$content = "source filename didn't match: ${sourcefileFullName}"
				LogWarn("${content}")
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
	$exceptionmessage = $_.Exception.Message
	$content = "Could not post to InfluxDB" + ";${sourcefileFullName}"
	LogError("${User};${CustomerId};${ServerName};${FromDateString};${ToDateString};${content}")	
	LogError("${exceptionmessage}")
}