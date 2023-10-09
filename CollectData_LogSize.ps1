#########################################################################
#
# Name: CollectData_LogSize.ps1
#
# Version: 1.0.1.38
#
# Description: ...
#
###############################################################################
param (
	[switch] $verbose
)
. ".\LoadFunctions.ps1"

#Scriptname for logging
$scriptname = "CollectData_LogSize.ps1"
$versiondate = "2023-07-25 15:43"
#Logging
$logger = CreateLogger("DiagnosticScripts")
$perflogger = CreateLogger("DiagnosticScripts.Performance")
$overwritelogger = CreateLogger("DiagnosticScripts.Overwrite")
$logobject = CreateLogObject($scriptname)
$lastexitcode			= 0

#$Config = GetConfig

$ServerName 		= $(Hostname).ToUpper()

$CustomerId			= GetConfigValue "customerid"
$planolog 			= GetConfigValue "paths.planolog"
$planoapp 			= GetConfigValue "paths.planoapp"
$interflexapp 		= GetConfigValue "paths.interflexapp"
$interflexlog 		= GetConfigValue "paths.interflexlog"
$planotemp			= GetConfigValue "paths.planotemp"
$anonymiseconfigs	= GetConfigValue "parameter.anonymiseconfigs"
$tisapp = GetConfigValue "paths.tisapp"
$tislog = GetConfigValue "paths.tislog"

LogInfo("Script started.")
LogInfo("Retrieving log size information.")
$stopwatchOverall = [System.Diagnostics.Stopwatch]::StartNew()
$stopwatchOverall.Restart()

$dateString = Get-Date -Format "yyyy-MM-dd"
# Function to get folder size in megabytes (KB) with comma-separated format
function Get-FolderSizeInKB {
    param(
        [string]$folderPath
    )
	try{
		LogInfo("Trying to retrieve log size information for ${folderPath}.")
		$folder = Get-Item $folderPath
		$sizeInKB = 0.0
		$sizeInBytes = (Get-ChildItem -Recurse -File -Path $folderPath | Measure-Object -Sum Length).Sum
		$sizeInKB = $sizeInBytes / 1024   # Convert bytes to
	}
	catch{
		LogError("Error retrieving log size information for ${folderPath}.")
		LogError("Exception: "+ $_.Exception.Message)
	}

    return "{0:N2}" -f $sizeInKB
}

# Function to get total size of log files with yesterday's date in
function Get-LogYday {
    param(
        [string]$folderPath
    )
	try{
		LogInfo("Trying to retrieve log size information for ${folderPath}.")
		$yesterday = (Get-Date).AddDays(-1).Date

		$files = Get-ChildItem -Path $folderPath -File | Where-Object { $_.LastWriteTime.Date -eq $yesterday }
		$totalSizeInKB = 0.0

		foreach ($file in $files) {
			$totalSize += $file.Length
		}
		$totalSizeInKB = $totalSize / 1024
	}
	catch{
		LogError("Error retrieving log size information for ${folderPath}.")
		LogError("Exception: "+ $_.Exception.Message)
	}
	
    return "{0:N2}" -f $totalSizeInKB
}

try{
	# Get sizes of the folders in 
	$planoTotal = Get-FolderSizeInKB -folderPath $planolog
	$interflexTotal = Get-FolderSizeInKB -folderPath $interflexlog
	if($tislog -eq "Default:PlanoLogPathIsUsed") {
		$ximesTotal = 0
	}
	else{
		$ximesTotal = Get-FolderSizeInKB -folderPath $ximeslog
	}

	$totalPlano1 = [double]::Parse($planoTotal)
	$totalInterflex1 = [double]::Parse($interflexTotal)
	$totalXimes1 = [double]::Parse($ximesTotal)

	$Totalsize = ($totalPlano1 + $totalInterflex1 + $totalXimes1) 

	$planoYday = Get-LogYday -folderPath $planolog
	$interflexYday = Get-LogYday -folderPath $interflexlog
	if($tislog -eq "Default:PlanoLogPathIsUsed") {
		$ximesYday = 0
	}
	else{
		$ximesYday = Get-LogYday -folderPath $ximeslog
	}
	
	$TotalplanoYday =[double]::Parse($planoYday)
	$TotalinterflexYday = [double]::Parse($interflexYday)
	$TotalximesYday = [double]::Parse($ximesYday)

	$TotalYday = ($TotalplanoYday + $TotalinterflexYday + $TotalximesYday)

	# array of custom objects to hold the log data
	$logData = @()

	$logData += [PSCustomObject]@{
		DateTime              = "$dateString"
		TheTotalsize          = "$Totalsize"
		TotalSize_FromYesterday  = "$TotalYday"
		Planolog_ActualSize   = "$totalPlano1"
		Planolog_YesterdaySize = "$TotalplanoYday"
		Interflexlog_ActualSize = "$totalInterflex1"
		Interflexlog_YesterdaySize = "$TotalinterflexYday"
		Ximeslog_ActualSize   = "$totalXimes1"
		Ximeslog_YesterdaySize = "$TotalximesYday"
	}

	$csvFilePath = "${planolog}\metrics\${CustomerId}_${ServerName}_LogSize_${dateString}.csv"

	$logData | Export-Csv -Path $csvFilePath -Delimiter ";" -NoTypeInformation -Encoding UTF8
}
catch{
	"1"
		LogError("Error retrieving log size information.")
		LogError("Exception: "+ $_.Exception.Message)
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