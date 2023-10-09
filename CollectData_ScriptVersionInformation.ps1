#########################################################################
#
# Name: CollectData_ScriptVersionInformation.ps1
#
# Version: 1.0.1.37
#
# Description: ...
#
#########################################################################

. ".\LoadFunctions.ps1"

#Scriptname for logging
$scriptname = "CollectData_ScriptVersionInformation.ps1" 
$scriptversion = "2023-07-25 15:43"

#Logging
$logger = CreateLogger("DiagnosticScripts")
$perflogger = CreateLogger("DiagnosticScripts.Performance")
$overwritelogger = CreateLogger("DiagnosticScripts.Overwrite")
$logobject = CreateLogObject($scriptname)

$Config = GetConfig
$CustomConfig = GetCustomConfig

$ServerName = 		$(Hostname).ToUpper()
$CustomerId			= GetConfigValue "customerid"

$diagnosticscriptspath = GetConfigValue "paths.statisticsapp" 
$planolog			= GetConfigValue "paths.planolog"
$targetpath			= "${planolog}\scriptversion"
$datestring = (Get-Date).tostring("yyyyMMdd")
mkdir $targetpath -Force > $null
$targetfile = "${targetpath}\${customerid}_${servername}_scriptversion_${datestring}.log"

LogInfo("Script started.")
LogOverwrite("Script ${scriptname} running version ${scriptversion}.")

$stopwatchOverall = [System.Diagnostics.Stopwatch]::StartNew()
$stopwatchOverall.Restart()

try{
	"Scriptname;Version" | Out-File "$targetfile" -Append
	Get-ChildItem $diagnosticscriptspath -Recurse -Include "*.ps1" |
		ForEach-Object {
			$versionNumber = (Get-Content $_.FullName) |
				Where-Object { $_ -match "Version:\s+(\d+\.\d+\.\d+\.\d+)" } |
				ForEach-Object { $Matches[1] }
			$updateInfo = (Get-Content $_.FullName) |
				Where-Object { $_ -match "Version:\s+\d+\.\d+\.\d+\.\d+\s*(.*)" } |
				ForEach-Object { $Matches[1].Trim() }
			if ($versionNumber) {
				$_.Name + ";" + $versionNumber + $updateInfo | Out-File "$targetfile" -Append
			}
			else {
				$_.Name + ";Version information not found" | Out-File "$targetfile" -Append
			}
		}
}
catch{
	LogError("Error retrieving script version info.")
	LogError("Error: " + $_.Exception.Message)
	$lastexitcode = 1
}

if ($lastexitcode -eq 0 -OR $null -eq $lastexitcode) {
	LogInfo("Script ended successfully.")
	$stopwatchOverall.Stop()
	$duration = $stopwatchOverall.Elapsed.TotalMilliSeconds.ToString() -replace ',','.'
	LogPerf -name "Overall" -duration "${duration}"
}
else {
	LogError("Script ended with error.")
	$stopwatchOverall.Stop()
}
