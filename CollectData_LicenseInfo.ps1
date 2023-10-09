#########################################################################
#
# Name: CollectData_LicenseInfo.ps1
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
$scriptname = "CollectData_LicenseInfo.ps1" 
$scriptversion = "2023-07-25 15:43"

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
$planotemp			= GetConfigValue "paths.planotemp"
$anonymiseconfigs	= GetConfigValue "parameter.anonymiseconfigs"
$tisapp = GetConfigValue "paths.tisapp"
$tislog = GetConfigValue "paths.tislog"

$planoconfiglog		= "${planolog}\configurations"
$conftempdir		= "${planotemp}\configurations"

LogInfo("Script started.")
LogOverwrite("Script ${scriptname} running version ${scriptversion}.")
$stopwatchOverall = [System.Diagnostics.Stopwatch]::StartNew()
$stopwatchOverall.Restart()

$today = [datetime]::Today
$dateString = $today.ToString("yyyy-MM-dd")

try{
	LogDebug("Retrieving license info from file.")
	
	if (Test-Path "${interflexapp}\SP-EXPERT Application Server64\License.txt"){
		$licenseFilePath = "${interflexapp}\SP-EXPERT Application Server64\License.txt"
	}
	elseif(Test-Path "${interflexapp}\SP-EXPERT Application Server\License.txt"){
		$licenseFilePath = "${interflexapp}\SP-EXPERT Application Server\License.txt"
	}
	else{
		$licenseFilePath = (Get-ChildItem -Path $interflexapp -Filter "License.txt" -Recurse | Select-Object -First 1).FullName
	}
	
	if (Test-Path $licenseFilePath){
		LogDebug("License file found inside DiagnosticScripts folder.")
		
		$licenseInfoResult = CheckLicenseFileWithFilePathAsCsv($licenseFilePath)
		if($licenseInfoResult -like "*;valid" -OR $licenseInfoResult -like "*;expired")
		{
			LogDebug("License info result contains a valid status.")
			$licenseInfoFile = "${planolog}\metrics\${CustomerId}_${ServerName}_licenseinfo_${dateString}.csv"
			if (!(Test-Path $licenseInfoFile)) { New-Item -ItemType "file" -Path $licenseInfoFile > $null }
			LogDebug("Writing license info to log path.")
			Set-Content -Path $licenseInfoFile -Value $licenseInfoResult > $null
			
		}
		else{
			LogWarn("License info result does not contain a valid status.")
		}
		
		$licenseInfo = CheckLicenseFileReturnObject($licenseFilePath)
		$licenseInfo = ConvertTo-Json $licenseInfo
		Set-Content -Path "${planolog}\metrics\${CustomerId}_${ServerName}_license_${dateString}.json" -Value $licenseInfo > $null
		
	}
	else{
		LogWarn("No license found.")
	}
	
}
catch{
	LogError("Error retrieving license info from file.")
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
