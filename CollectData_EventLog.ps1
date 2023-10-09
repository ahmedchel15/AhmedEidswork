#########################################################################
#
# Name: CollectData_EventLog.ps1
#
# Version: 1.0.1.38
#
# Description: Collects the event logs as files from windows event log
#
###########################################################################

param (
    [switch] $verbose
)
. ".\LoadFunctions.ps1"

#Scriptname for logging
$scriptname = "CollectData_EventLog.ps1" 
$scriptversion = "2023-07-25 15:43"

#Logging
$logger = CreateLogger("DiagnosticScripts")
$perflogger = CreateLogger("DiagnosticScripts.Performance")
$overwritelogger = CreateLogger("DiagnosticScripts.Overwrite")
$logobject = CreateLogObject($scriptname)
$lastexitcode        = 0

#$Config = GetConfig
$planolog           = GetConfigValue "paths.planolog"

# Eventlogs
$yesterday  = (Get-Date).AddDays(-1).Date
# Excluded sources and levels for Application log
$excludedApplicatonSources = @("Net Runtime", ".Net Runtime Optimization Service", "ASP.NET 4.0.30319.0", "IF6040", "IF6040 Job Sheduler", "IF6040-DataExchange","ISS*","plano*")
$ApplicationentryTypes = @("Error", "Warning")

# Excluded sources and levels for System log
$excludedSystemSources = @("WAS", "IIS-APPHOSTSVC")
$systemEntryTypes = @("Error", "Warning")

# Retrieve logs from Applications and Services Logs for specified sources and all levels
$appAndServicesEntryTypes = @("Error", "Information", "FailureAudit", "SuccessAudit", "Warning")

LogInfo("Script started.")
LogOverwrite("Script ${scriptname} running version ${scriptversion}.")
$stopwatchOverall = [System.Diagnostics.Stopwatch]::StartNew()
$stopwatchOverall.Restart()

try {
    LogInfo("Try getting event logs.")

    try{
		LogDebug("Try getting application event logs.")
		$eventApplicationLog   = Get-EventLog -LogName Application -EntryType $ApplicationentryTypes -After $yesterday -Before (Get-Date) | Where-Object { $excludedApplicatonSources -contains $_.Source }
    }
    catch{
        LogError("Error getting event logs for application.")
        LogError("Error : + $_.Exception.Message")
    }

    try{
		LogDebug("Try getting system event logs.")
		$eventSystemLog = Get-EventLog -LogName System -EntryType $systemEntryTypes -After $yesterday -Before (Get-Date) | Where-Object { $excludedSystemSources -contains $_.Source }
	}
	catch{
		LogError("Error getting event logs for system.")
		LogError("Error : + $_.Exception.Message")
	}
		
	try{
		LogDebug("Try getting plano event logs.")
		$eventAppAndServicePlanolog = Get-EventLog -LogName plano -EntryType $appAndServicesEntryTypes -After $yesterday -Before (Get-Date)
	}
	catch{
		LogError("Error getting event logs for plano.")
		LogError("Error : + $_.Exception.Message")
	}
	try{
		LogDebug("Try getting redis event logs.")
		$eventAppAndServiceRedislog = Get-EventLog -LogName redis -EntryType $appAndServicesEntryTypes -After $yesterday -Before (Get-Date)
		$eventAppAndServiceRedislog.Count
	}

	catch{
		LogError("Error getting event logs for redis.")
		LogError("Error : + $_.Exception.Message")
	}
    
    $eventlogFolder = "${planolog}\eventlog"


# Check if the event logfolder already exists
if (-not (Test-Path -Path $eventlogFolder)) {
    # Create the folder
    New-Item -ItemType Directory -Path $eventlogFolder > $null
    LogDebug("Eventlog folder created successfully.")
} else {
	LogDebug("Eventlog folder already exists.")
}

# Check if the event log subfolders already exist
foreach ($eventlogSubfolder in "application","system","plano","redis","other") {
	if (-not (Test-Path -Path "${eventlogFolder}\${eventlogSubfolder}")) {
		# Create the folder
		New-Item -ItemType Directory -Path "${eventlogFolder}\${eventlogSubfolder}" > $null
		LogDebug("Eventlog sub folder created successfully.")
	} else {
		LogDebug("Eventlog sub folder already exists.")
	}
}

$alleventlogs = @()
$alleventlogs += $eventApplicationLog
$alleventlogs += $eventSystemLog
$alleventlogs += $eventAppAndServicePlanolog
$alleventlogs += $eventAppAndServiceRedislog

# Process each event log entry
	foreach ($event in $alleventlogs) {
		try{
			$eventtypefolder = ""
			if($eventApplicationLog -Contains $event) 
				{$eventtypefolder = "application"}
			elseif($eventSystemLog -Contains $event) 
				{$eventtypefolder = "system"}
			elseif($eventAppAndServicePlanolog -Contains $event) 
				{$eventtypefolder = "plano"}
			elseif($eventAppAndServiceRedislog -Contains $event) 
				{$eventtypefolder = "redis"}
			else 
				{$eventtypefolder = "other"}
			
			LogDebug("Processing event log.")
			$eventTime  = $event.TimeGenerated
			$source     = $event.Source
			$entryType  = $event.EntryType

			# Format the date in the desired format (e.g., YYYY-MM-DD_HH-mm-ss)
			$dateString = $eventTime.ToString("yyyy-MM-dd_HH-mm-ss")

			# Generate the file name based on Entry Type, Source, and Date
			$fileName   = "${eventlogFolder}\${eventtypefolder}\$source-$entryType-$dateString.log"

			$logContent = "Event Time: $($eventTime)`r`n"
			$logContent += "Event ID: $($event.EventID)`r`n"
			$logContent += "Message: $($event.Message)`r`n"
			$logContent += "--------------------------`r`n"

			$logContent | Out-File -FilePath $fileName -Append
			$exportPath = "${planolog}\eventlog"
	
			# Create the export path directory if it doesn't exist
			if (!(Test-Path -PathType Container $exportPath)) {
				LogDebug("Try ceating export directory.")
				New-Item -ItemType Directory -Path $exportPath > $null
			}
		}
		catch{
			LogError("Error getting event logs.")
			LogError("Error: " + $_.Exception.Message)
		}

    }
    LogInfo("Getting event logs finished.")
}
catch {
    LogError("Error getting event logs.")
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
}
