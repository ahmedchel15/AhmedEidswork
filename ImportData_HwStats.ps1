#########################################################################
#
# Name: ImportData_HwStats.ps1
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

$dataFolder = "${customerFolder}\logs\${servername}\hwstats" 
if (-not (Test-Path $dataFolder)) {
	"ERROR: Folder does not exist: ${dataFolder}"
	"Probably not a Roster server"
	exit 1
}

if ($fromDateString -eq "") { $fromDate = [datetime]::Today.AddDays(-1)} else { $fromDate = [datetime]::ParseExact($fromDateString, "yyyy-MM-dd", $null) }
if ($toDateString -eq "") { $toDate = [datetime]::Today.AddDays(-1) } else { $toDate = [datetime]::ParseExact($toDateString, "yyyy-MM-dd", $null) }
if ($fromDate -gt $toDate) { $fromDate = $toDate }

$dotnet = "C:\\Program Files\\dotnet\\dotnet.exe"

$scriptName = "ImportData_HwStats.ps1"
Write-Host "Script ${scriptName} started." -ForegroundColor "DarkGreen"
$scriptPath = split-path -Parent $MyInvocation.MyCommand.Definition
. "${scriptPath}\LoadFunctions.ps1"

#Logging
$logger = CreateLogger("Statistics")
$logobject = CreateLogObject($scriptname)

for($date = $fromDate; $date -le $toDate; $date = $date.AddDays(1)) {
	
	$dateString = $date.ToString("yyyy-MM-dd")
    #$dateString
    
	$sourcefiles = Get-ChildItem -Path $dataFolder -Filter *_hwstats_${datestring}.csv -File -recurse 
	Foreach ($sourcefile in $sourcefiles) 
	{
		$sourcefileFullName = $sourcefile.FullName

		if ($sourcefile.length -ne 0)
		{
            Write-Host "${sourcefileFullName}" -ForegroundColor "Cyan"
			
			#Remove full stops from tag values
			$servername = $servername -replace '\.', '_'
			$servername = $servername.ToUpper()
			$customerid = $customerid -replace '\.', '_'
			
			try {
				& ${dotnet} ${scriptPath}\Tools\Import\plano.Statistics.Tools.Import.dll --customer "${customerid}" --server "${servername}" --intype "hwstats" --infile "${sourcefileFullName}" --date "${dateString}"		
			}
			catch {
				$content = $_.Exception.Message
				LogError("${content}")	
			}
		}	
		else {
			$content = "warn: file has a size of 0 bytes: ${sourcefileFullName}"
			#LogDebug("${content}")
		}
	} #foreach sourcefiles

} #for($date)
