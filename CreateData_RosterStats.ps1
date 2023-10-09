#########################################################################
#
# Name: CreateData_RosterStats.ps1
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

$scriptName = "CreateData_RosterStats.ps1"
Write-Host "Script ${scriptName} started." -ForegroundColor "DarkGreen"
$scriptPath = split-path -Parent $MyInvocation.MyCommand.Definition
. "${scriptPath}\LoadFunctions.ps1"

#Logging
$logger = CreateLogger("Statistics")
$logobject = CreateLogObject($scriptname)

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
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

$logsFolder = "${customerFolder}\logs\${servername}\rosterstats" 

if (-not (Test-Path $logsFolder)) {
	"ERROR: Folder does not exist: ${logsfolder}"
	"Probably not a Roster server"
	exit 1
}


$dataFolder = "${customerFolder}\data\${servername}\rosterstats" 
mkdir $dataFolder -Force > $null

if ($fromDateString -eq "") { $fromDate = [datetime]::Today.AddDays(-1)} else { $fromDate = [datetime]::ParseExact($fromDateString, "yyyy-MM-dd", $null) }
if ($toDateString -eq "") { $toDate = [datetime]::Today.AddDays(-1) } else { $toDate = [datetime]::ParseExact($toDateString, "yyyy-MM-dd", $null) }
if ($fromDate -gt $toDate) { $fromDate = $toDate }


for($date = $fromDate; $date -le $toDate; $date = $date.AddDays(1)) {
	
	$dateString = $date.ToString("yyyy-MM-dd")
	$dateString1 = $date.ToString("yyyyMMdd")

	#Count distinct planners
	$distinctPlanners = 0
	$distinctObject = @()

	$sourcefiles = Get-ChildItem -LiteralPath "$logsFolder" -Filter *_rosterstats_${datestring1}-*.log -File -Recurse 

	if ($sourcefiles.length -ne 0)
	{
		$targetfileFullName = "${dataFolder}\${customerid}_${servername}_rosterstats_${dateString}.csv"
		Remove-Item "${targetfileFullName}" -Force -ErrorAction SilentlyContinue

		$header = """customerid"";""servername"";""datetime"";""activesessions"";""totalplanners"";""totalschedules"";""totalemployees"";""totalemployeedays"";""totallinks"";""notconnectedschedules"";""notconnectedemployees"";""notconnectedemployeedays"";""notconnectedlinks"";""pendingColumnValues"";""availableSpxWorkers""" 

		$outfilestream = New-Object System.IO.StreamWriter $targetfileFullName
		$outfilestream.WriteLine($header)

		Foreach ($sourcefile in $sourcefiles) {

			$sourcefileFullName = $sourcefile.FullName
			$matchstring = ".*\\.*_rosterstats_${datestring1}-(\d\d)(\d\d).log"

			if ($sourcefileFullName -match $matchstring)
			{
				$hours = $matches[1]
				$minutes = [int]($matches[2])
				$roundedMinutes = ([math]::Round($minutes / 15) * 15).ToString("00")   #we round to 15min, so it's always like this and can be aggregated and compared
				if ($roundedMinutes -eq "60") { $roundedMinutes = "00" }
				$timestring = $hours + $roundedMinutes

				$data = ""
				try {
					$data = (Get-Content -LiteralPath "$sourcefileFullName" | ConvertFrom-Json)
				}
				catch {
					LogWarn("Warn: file contains no valid json data: ${sourcefileFullName}")
					"Warn: file contains no valid json data: ${sourcefileFullName}"
				}
				
				if ($data -ne "") {
					try {
						$activesessions = (($data | Select-Object -Expand activeSessions | Select-Object -Property userName -ExpandProperty userName).Count) ?? 0
						$totalplanners = (($data | Select-Object -Expand activeSessions | Select-Object -Property userName -ExpandProperty userName -Unique).Count) ?? 0
						$distinctObject += ($data | Select-Object -Expand activeSessions | Select-Object -Property userName -ExpandProperty userName -Unique)
						
						$totalschedules = ((($data | Select-Object -Property rosters -Expand rosters) | Measure-Object).Count) ?? 0
						$totalemployees = ($data | Select-Object -Expand rosters | Measure-Object -Property employeesCount -sum | Select-Object -expand Sum) ?? 0
				
						# $rosterobject = $data | Select-Object -Expand rosters

						# $count = $rosterobject| Measure-Object -Property employeesCount -sum | Select-Object -expand Sum
						# $count

						$totalemployeeDays = ($data | Select-Object -Expand rosters | Measure-Object -Property employeeDaysCount -sum | Select-Object -expand Sum) ?? 0
						$notconnectedemployeeDays = (($data | Select-Object -Expand rosters | Where-Object { $_.connectedViews.Count -eq 0 })| Measure-Object -Property employeeDaysCount -sum | Select-Object -expand Sum) ?? 0

						# "employeeDaysCount" was added in Roster in version 1.31, not existing at customers before this version
						# if ("employeeDaysCount" -in $rosterobject.PSobject.Properties.Name)
						# {
						# 	"employeeDaysCount EXISTING"
						# 	$totalemployeeDays = $data | Select-Object -Expand rosters | Measure-Object -Property employeeDaysCount -sum | Select-Object -expand Sum
						# 	$notconnectedemployeeDays = ($data | Select-Object -Expand rosters | Where-Object { $_.connectedViews.Count -eq 0 })| Measure-Object -Property employeeDaysCount -sum | Select-Object -expand Sum
						# } 
						# else 
						# {
						# 	"employeeDaysCount NOT EXISTING"
						# 	$totalemployeeDays = 0
						# 	$notconnectedemployeeDays = 0
						# }

						$totallinks = ($data | Select-Object -Expand rosters | Measure-Object -Property linksCount -sum | Select-Object -expand Sum) ?? 0

						$notconnectedschedules = ((($data | Select-Object -Expand rosters | Where-Object { $_.connectedViews.Count -eq 0 }) | Measure-Object).Count) ?? 0
						$notconnectedemployees = (($data | Select-Object -Expand rosters | Where-Object { $_.connectedViews.Count -eq 0 })| Measure-Object -Property employeesCount -sum | Select-Object -expand Sum) ?? 0
						$notconnectedlinks = (($data | Select-Object -Expand rosters | Where-Object { $_.connectedViews.Count -eq 0 })| Measure-Object -Property linksCount -sum | Select-Object -expand Sum) ?? 0 
				
						$pendingColumnValues = ($data | Select-Object -Expand rosters | Select-Object -Expand connectedViews | Measure-Object -Property pendingColumnValuesRequestsCount -sum | Select-Object -expand Sum) ?? 0
						$availableSpxWorkers = ($data | Select-Object -Expand spxProviderStatus | Select-Object -Property availableSpxWorkers -ExpandProperty availableSpxWorkers) ?? 0
						
						$output = """${customerid}"";""${servername}"";""${datestring1}${timestring}"";${activesessions};${totalplanners};${totalschedules};${totalemployees};${totalemployeeDays};${totallinks};${notconnectedschedules};${notconnectedemployees};${notconnectedemployeeDays};${notconnectedlinks};${pendingColumnValues};${availableSpxWorkers}" 
					}
					catch {
						LogError("Error: Could not parse file content: ${sourcefileFullName}")
						LogError("Error: " + $_.Exception.Message)
						"Error: Could not parse file content: ${sourcefileFullName}"
						"Error: " + $_.Exception.Message
					}
					
					try {
						$outfilestream.WriteLine($output)
					}
					catch {
						LogError("Error: Could not Write to file: ${sourcefileFullName}")
						LogError("Error: " + $_.Exception.Message)
						"Error: Could not Write to file: ${sourcefileFullName}"
						"Error: " + $_.Exception.Message
					}
				}
			}
			else {
				LogWarn("Warn: source filename didn't match: ${sourcefileFullName}")
				"Warn: source filename didn't match: ${sourcefileFullName}"
				#exit 1
			}
		}
	} #if ($sourcefiles -ne "")
	
	try {
		if($outfilestream.BaseStream){
			$outfilestream.Close()
		}
	}
	catch {
		LogError("Error closing file stream.")
		LogError("Error: " + $_.Exception.Message)
		"Error closing file stream."
		"Error: " + $_.Exception.Message
	}
	
	#Create file for distinct planners
	try {
		$targetfileFullNameDistinct = "${dataFolder}\${customerid}_${servername}_rosterstats_distinctplanners_${dateString}.csv"
		Remove-Item "${targetfileFullNameDistinct}" -Force -ErrorAction SilentlyContinue
		$headerD = """customerid"";""servername"";""datetime"";""disctinctplanners"""
		$outfilestreamDistinct = New-Object System.IO.StreamWriter $targetfileFullNameDistinct
		$outfilestreamDistinct.WriteLine($headerD)
		$distinctPlanners = ($distinctObject | Group-Object -NoElement | Select-Object -expand Name).Count
		$outputDistinct = """${customerid}"";""${servername}"";""${datestring1}0000"";${distinctPlanners}" 
		$outfilestreamDistinct.WriteLine($outputDistinct)
		$outfilestreamDistinct.Close()
		
		try{
			$targetfileFullNameDistinctList = "${dataFolder}\${customerid}_${servername}_rosterstats_distinctplannerslist_${dateString}.csv"
			Remove-Item "${targetfileFullNameDistinctList}" -Force -ErrorAction SilentlyContinue
			$outfilestreamDistinctList = New-Object System.IO.StreamWriter $targetfileFullNameDistinctList
			foreach($planner in $distinctObject)
			{
				$outfilestreamDistinctList.WriteLine($planner)
			}
			$outfilestreamDistinctList.WriteLine($outputDistinct)
			$outfilestreamDistinctList.Close()
		}
		catch {
			LogError("Error creating list for distinct planners.")
			LogError("Error: " + $_.Exception.Message)
			"Error creating list for distinct planners."
			"Error: " + $_.Exception.Message
		}
	}
	catch {
		LogError("Error creating file for distinct planners.")
		LogError("Error: " + $_.Exception.Message)
		"Error creating file for distinct planners."
		"Error: " + $_.Exception.Message
	}
	
} #for($date
