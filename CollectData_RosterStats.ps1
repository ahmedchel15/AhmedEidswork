#########################################################################
#
# Name: CollectData_RosterStats.ps1
#
# Version: 1.0.1.38
#
# Description: ...
#
# setup in Roster
# ---------------
# add the following key in the appSettings section of file:
# C:\Program Files (x86)\plano\Services\RosterService\plano.RosterService.appSettings.custom.config
# <add key="plano.Roster.RosterStats.ApiKey" value="<secret>" /> 
#
# if it is not set up correctly, page will show:
# Feature disabled. Add '<add key="plano.Roster.RosterStats.ApiKey" value="<secret>" />' to the app.config of the RosterService.
#
#########################################################################

. ".\LoadFunctions.ps1"

Add-Type -AssemblyName System.Web

#Scriptname for logging
$scriptname = "CollectData_DatabaseStats.ps1" 
$scriptversion = "2023-07-25 15:43"

#$Config = 			GetConfig

$ServerName = 		$(Hostname).ToUpper()

$CustomerId			= GetConfigValue "customerid"
$planolog			= GetConfigValue "paths.planolog"
$statusurisecret	= GetConfigValue "roster.statusurisecret"
$statusurisecret	= [System.Web.HttpUtility]::UrlEncode($statusurisecret)
$statusuri			= GetConfigValue "roster.statusuri"
$targetpath			= "${planolog}\rosterstats"
$completeuri		= "${statusuri}${statusurisecret}"

#Logging
$logger = CreateLogger("DiagnosticScripts")
$perflogger = CreateLogger("DiagnosticScripts.Performance")
$overwritelogger = CreateLogger("DiagnosticScripts.Overwrite")
$logobject = CreateLogObject($scriptname)

###########################################################################
#
mkdir $targetpath -Force > $null
$datestring = (Get-Date).tostring("yyyyMMdd-HHmm")
$targetfile = "${targetpath}\${customerid}_${servername}_rosterstats_${datestring}.log"

$psversion = $PSVersionTable.PSVersion.Major
$page = ""
if ($psversion -eq "6") {
	$page = (Invoke-WebRequest -UseBasicParsing -ContentType "application/json" -Body null -Uri "$completeuri").Content
}
else {
	$page = (Invoke-WebRequest -UseBasicParsing -ContentType "application/json" -Uri "$completeuri").Content
}

if ($page -like "*identityserver*") {
	
	#TODO: error handling should be better here --> but could also be logged into same file
	"Error: result page contains text 'identityserver'. That means, that the roster/home/status-call doesn't work correctly." | Out-File "$targetfile"
	exit 1
}
elseif ($page -like "*Feature disabled*") {
	$page | Out-File "$targetfile"
	exit 1
}
else {
	$page | Out-File "$targetfile"
	
	$rosterstatsasperfcounter	= GetConfigValue "parameter.rosterstatsasperfcounter"
	if($rosterstatsasperfcounter -eq $false -OR $null -eq $rosterstatsasperfcounter)
	{
		LogInfo("Writing roster stats as performance counter is disabled.")
	}
	else{
		$page = ConvertFrom-Json $page
		$counterCategory = "plano Roster Stats"
		try{
			try{
				$activesessions = ($page | Select-Object -Expand activeSessions | Select-Object -Property userName -ExpandProperty userName).Count 
			}
			catch{
				$activesessions = 0
			}
			$RosterSession = New-Object System.Diagnostics.PerformanceCounter($counterCategory, "Session", $false)
			$RosterSession.RawValue = $activesessions
		}
		catch{
			LogError("An error occurred while updating performance counter Session.")
			LogError("Error: " + $_.Exception.Message)
		}
		
		try{
			try{
				$totalplanners = ($page | Select-Object -Expand activeSessions | Select-Object -Property userName -ExpandProperty userName -Unique).Count
			}
			catch{
				$totalplanners = 0
			}
			$RosterPlanners = New-Object System.Diagnostics.PerformanceCounter($counterCategory, "Planners", $false)
			$RosterPlanners.RawValue = $totalplanners
		}
		catch{
			LogError("An error occurred while updating performance counter Planners.")
			LogError("Error: " + $_.Exception.Message)
		}
		
		try{
			try{
				$totalschedules = (($page | Select-Object -Property rosters -Expand rosters) | Measure-Object).Count
			}
			catch{
				$totalschedules = 0
			}
			$RosterSchedules = New-Object System.Diagnostics.PerformanceCounter($counterCategory, "Schedules", $false)
			$RosterSchedules.RawValue = $totalschedules
		}
		catch{
			LogError("An error occurred while updating performance counter Schedules.")
			LogError("Error: " + $_.Exception.Message)
		}

		try{
			try{
				$totalemployees = $page | Select-Object -Expand rosters | Measure-Object -Property employeesCount -sum | Select-Object -expand Sum
			}
			catch{
				$totalemployees = 0
			}
			$RosterEmployees = New-Object System.Diagnostics.PerformanceCounter($counterCategory, "Employees", $false)
			$RosterEmployees.RawValue = $totalemployees
		}
		catch{
			LogError("An error occurred while updating performance counter Employees.")
			LogError("Error: " + $_.Exception.Message)
		}

		try{
			try{
				$totalemployeeDays = $page | Select-Object -Expand rosters | Measure-Object -Property employeeDaysCount -sum | Select-Object -expand Sum
			}
			catch{
				$totalemployeeDays = 0
			}
			$RosterEmployeeDays = New-Object System.Diagnostics.PerformanceCounter($counterCategory, "EmployeeDays", $false)
			$RosterEmployeeDays.RawValue = $totalemployeeDays
		}
		catch{
			LogError("An error occurred while updating performance counter EmployeeDays.")
			LogError("Error: " + $_.Exception.Message)
		}

		try{
			try{
				$totallinks = ($data | Select-Object -Expand rosters | Measure-Object -Property linksCount -sum | Select-Object -expand Sum)
			}
			catch{
				$totallinks = 0
			}
			$RosterLinks = New-Object System.Diagnostics.PerformanceCounter($counterCategory, "Links", $false)
			$RosterLinks.RawValue = $totallinks
		}
		catch{
			LogError("An error occurred while updating performance counter Links.")
			LogError("Error: " + $_.Exception.Message)
		}

		try{
			try{
				$notconnectedschedules = (($page | Select-Object -Expand rosters | Where-Object { $_.connectedViews.Count -eq 0 }) | Measure-Object).Count
			}
			catch{
				$notconnectedschedules = 0
			}
			$RosterUnconnectedSchedules = New-Object System.Diagnostics.PerformanceCounter($counterCategory, "UnconnectedSchedules", $false)
			$RosterUnconnectedSchedules.RawValue = $notconnectedschedules
		}
		catch{
			LogError("An error occurred while updating performance counter UnconnectedSchedules.")
			LogError("Error: " + $_.Exception.Message)
		}
	}
}
