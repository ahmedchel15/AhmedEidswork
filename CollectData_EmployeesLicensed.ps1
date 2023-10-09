#########################################################################
#
# Name: CollectData_EmployeesLicensed.ps1
#
# Version: 1.0.1.37-updat02
#
# Description: ...
#
#########################################################################

. ".\LoadFunctions.ps1"

#Scriptname for logging
$scriptname = "CollectData_EmployeesLicensed.ps1" 
$scriptversion = "2023-07-25 15:43"

#Logging
$logger = CreateLogger("DiagnosticScripts")
$perflogger = CreateLogger("DiagnosticScripts.Performance")
$overwritelogger = CreateLogger("DiagnosticScripts.Overwrite")
$logobject = CreateLogObject($scriptname)

$CustomerId 	= GetConfigValue "customerid"
$planolog 		= GetConfigValue "paths.planolog"
$statisticsapp 		= GetConfigValue "paths.statisticsapp"
$interflexapp 		= GetConfigValue "paths.interflexapp"
$targetpath 	= "${planolog}\serverinfo"
$ServerName 	= $(Hostname).ToUpper()
$createdatabasestats = GetConfigValue "parameter.createdatabasestats"

###########################################################################
LogInfo("Script started.")
LogOverwrite("Script ${scriptname} running version ${scriptversion}.")
$stopwatchOverall = [System.Diagnostics.Stopwatch]::StartNew()
$stopwatchOverall.Restart()

try{
	if($createdatabasestats.ToLower() -eq "true" -OR $createdatabasestats -eq $true)
	{
		$datestring = (Get-Date).tostring("yyyy-MM-dd")
		$targetfile = "${targetpath}\${CustomerId}_${ServerName}_licensedemployees_${datestring}.log"

		$xmlFile = "${statisticsapp}\plano.license"
		$outputPath = "${planolog}\metrics"

		$sixMonthsAgo = (Get-Date).AddMonths(-6)

		# Load license
		if (Test-Path "${interflexapp}\SP-EXPERT Application Server64\License.txt"){
			$licenseFilePath = "${interflexapp}\SP-EXPERT Application Server64\License.txt"
		}
		elseif(Test-Path "${interflexapp}\SP-EXPERT Application Server\License.txt"){
			$licenseFilePath = "${interflexapp}\SP-EXPERT Application Server\License.txt"
		}
		else{
			$licenseFilePath = (Get-ChildItem -Path $interflexapp -Filter "License.txt" -Recurse | Select-Object -First 1).FullName
		}
		
		$licenseInfo = CheckLicenseFileReturnObject($licenseFilePath)

		$maximum = 0
		$minimum = 0

		
		if(Test-Path "${planolog}\metrics\*_employeeslicensed_${datestring}.csv")
		{
			try{
				LogDebug("Found metric file for licensed employees. Creating metric.")
				
				$Mitarbeiter = Import-CSV -path "${planolog}\metrics\*_employeeslicensed_${datestring}.csv" -Delimiter ";"
				$allemployees = $Mitarbeiter.AllEmployees

				LogInfo("The system contains ${allemployees} employees (Total).")

				$licensedemployees = $Mitarbeiter.LicensedEmployee
				$licensedmodules = $licenseInfo.Modules
				LogInfo("The system contains ${licensedemployees} employees (Licensed).")

				foreach ($licensedmodule in $licensedmodules) {
					
					if($licensedmodule -eq "Counter")
					{
						$number = $licensedmodule.Info
					}
					
					if($maximum -eq 0)
					{
						$maximum = $number 
					}

					if($minimum -eq 0)
					{
						$minimum = $number 
					}

					if ($number -gt $maximum) {
						$maximum = $number
						Write-Host "New Maximum licensed employees are $maximum"
					}
					elseif ($number -lt $minimum) {
						$minimum = $number
						#Write-Host "New Minimum licensed employees are $minimum"
					}
				}

				LogInfo("The system contains ${maximum} employees in one license bit.")
				LogInfo("The system contains ${minimum} employees in one license bit.")

				if(Test-Path $targetfile)
				{
					Remove-Item $targetfile
					LogDebug("Removed ${targetfile} successfully.")
				}
				$output = "allemployees;licensedemployees;miniumlicense;maximumlicense`n"
				$output += "${allemployees};${licensedemployees};${minimum};${maximum}"
				$output | Out-File $targetfile
			}
			catch{
				LogError("Error retrieving server info.")
				LogError("Error: " + $_.Exception.Message)
				$lastexitcode = 1
			}
		}
		else{
			LogDebug("Metric file for licensed employyes does not exist. Skipping.")
		}
	}
	else{
		LogDebug("CreateDatabaseStats is disabled for this server. Skipping.")
	}
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
