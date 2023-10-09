#########################################################################
#
# Name: CollectData_ServerInformation.ps1
#
# Version: 1.0.1.38
#
# Description: Collects system information about the server and outputs it to a file.
#
#########################################################################

. ".\LoadFunctions.ps1"

#Scriptname for logging
$scriptname = "CollectData_ServerInformation.ps1" 
$scriptversion = "2023-07-25 15:43"

#Logging
$logger = CreateLogger("DiagnosticScripts")
$perflogger = CreateLogger("DiagnosticScripts.Performance")
$overwritelogger = CreateLogger("DiagnosticScripts.Overwrite")
$logobject = CreateLogObject($scriptname)

$CustomerId 	= GetConfigValue "customerid"
$planolog 		= GetConfigValue "paths.planolog"
$targetpath 	= "${planolog}\serverinfo"
$ServerName 	= $(Hostname).ToUpper()

###########################################################################
LogInfo("Script started.")
LogOverwrite("Script ${scriptname} running version ${scriptversion}.")

$stopwatchOverall = [System.Diagnostics.Stopwatch]::StartNew()
$stopwatchOverall.Restart()

mkdir $targetpath -Force > $null
$datestring = (Get-Date).tostring("yyyy-MM-dd")
$targetfile = "${targetpath}\${CustomerId}_${ServerName}_serverinfo_${datestring}.log"
try{
	Get-ComputerInfo | ConvertTo-Json | Out-File -LiteralPath $targetfile
}
catch{
	LogError("Error retrieving server info.")
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
