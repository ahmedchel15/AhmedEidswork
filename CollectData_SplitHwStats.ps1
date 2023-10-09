#########################################################################
#
# Name: CollectData_SplitHwStats.ps1
#
# Version: 1.0.1.38
#
# Description: ...
#
#########################################################################
param(
	[string]$fromDateString
)

###############################################################################
. ".\LoadFunctions.ps1"


#Scriptname for logging
$scriptname = "CollectData_SplitHwStats.ps1" 
$scriptversion = "2023-07-25 15:43"

#Logging
$logger = CreateLogger("DiagnosticScripts")
$perflogger = CreateLogger("DiagnosticScripts.Performance")
$overwritelogger = CreateLogger("DiagnosticScripts.Overwrite")
$logobject = CreateLogObject($scriptname)

LogInfo("Script started.")
LogOverwrite("Script ${scriptname} running version ${scriptversion}.")

$stopwatchOverall = [System.Diagnostics.Stopwatch]::StartNew()
$stopwatchOverall.Restart()

$planolog = GetConfigValue "paths.planolog"

try{
	$sourcePath = "${planolog}\hwstats"
	$targetPath = "${planolog}\hwstats"

	$fromDate = [datetime]::Today.AddDays(-1)
	$fromDateString = $fromDate.ToString("yyyy-MM-dd")
	$toDate = [datetime]::Today
	$toDateString = $fromDate.ToString("yyyy-MM-dd")
	$csvFiles = @(Get-ChildItem -Path $sourcePath -Filter "*hwstats_${fromDateString}*.csv" | Where-Object { $_.LastWriteTime -gt $fromDate })
	$csvFiles += @(Get-ChildItem -Path $sourcePath -Filter "*hwstats_${toDateString}*.csv" | Where-Object { $_.LastWriteTime -gt $fromDate })
	
	foreach ($csvFile in $csvFiles) {
			
		$data = Import-Csv $csvFile.FullName -Delimiter ";"
		$headers = $data[0].PSObject.Properties.Name

		$serviceHeader = $headers | Where-Object { $_ -like "Process*" -or $_ -like "DateTime" }
		$webHeader = $headers | Where-Object { $_ -like "WEB*" -or $_ -like "DateTime"  }
		$systemHeader = $headers | Where-Object { $_ -like "System*" -or $_ -like "DateTime"  }
		$CounterRosterHeader =$headers | where-Object{ $_ -like "Special_Roster*" -or $_ -like "DateTime" }
		
		$separatorhwstats = "_hwstats_"
		$csvparts = $csvFile.BaseName -split $separatorhwstats, 0, "simplematch"
		
		$logFileRoster = Join-Path -Path $targetPath -ChildPath ( $csvparts[0] + $separatorhwstats + "Roster_" + $csvparts[1] + ".csv")
		$logFileService = Join-Path -Path $targetPath -ChildPath ( $csvparts[0] + $separatorhwstats + "Service_" + $csvparts[1] + ".csv")	
		$logFileWeb = Join-Path -Path $targetPath -ChildPath ( $csvparts[0] + $separatorhwstats + "Web_" + $csvparts[1] + ".csv")
		$logFileSystem = Join-Path -Path $targetPath -ChildPath ( $csvparts[0] + $separatorhwstats + "System_" + $csvparts[1] + ".csv")   

		$selectedColumnsRoster = @()
		$selectedColumnsService = @()
		$selectedColumnsWeb = @()
		$selectedColumnsSystem = @()
		
		
		foreach ($header in  $CounterRosterHeader) {
			
			if ( $header -like "DateTime" )  
			{ 
				$selectedColumnsRoster += $header
				$selectedColumnsService += $header
				$selectedColumnsWeb += $header
				$selectedColumnsSystem += $header
			}
			elseif ( $serviceHeader.Contains($header) )
			{ 
				$selectedColumnsService += $header
			}
			elseif ( $webHeader.Contains($header) )
			{ 
				$selectedColumnsWeb += $header
			}
			elseif ( $systemHeader.Contains($header) )
			{ 
				$selectedColumnsSystem += $header
			}
			elseif ( $CounterRosterHeader.Contains($header) )
			{ 
				$selectedColumnsRoster += $header
			}
			
		}
			
		$data | Select-Object $selectedColumnsRoster | Export-Csv -Path $logFileRoster -Delimiter ";" -NoTypeInformation
		$data | Select-Object $selectedColumnsService | Export-Csv -Path $logFileService -Delimiter ";" -NoTypeInformation
		$data | Select-Object $selectedColumnsWeb | Export-Csv -Path $logFileWeb -Delimiter ";" -NoTypeInformation
		$data | Select-Object $selectedColumnsSystem | Export-Csv -Path $logFileSystem -Delimiter ";" -NoTypeInformation
		
	}

}
catch
{
	LogError("An error occured during splitting HwStats.")
	LogError("Error: " + $_.Exception.Message)
	$lastexitcode = 1
}

try{
	LogDebug("Running Powershell garbage collection after script execution.")
	[system.gc]::Collect()
	[system.gc]::WaitForPendingFinalizers()
}
catch
{
	LogError("An error occured during Powershell garbage collection.")
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
