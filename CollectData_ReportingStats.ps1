#########################################################################
#
# Name: CollectData_ReportingStats.ps1
#
# Version: 1.0.1.38
#
# Description: ...
#
# setup in ReportingService
# ---------------
# add the following key in the appSettings section of file:
# C:\Program Files (x86)\plano\Websites\ReportingService\Web.config
# <add key="plano.Reporting.ReportingStats.ApiKey" value="<secret>"/>
#
# if it is not set up correctly, page will show:
# "Feature disabled. Add '<add key="plano.Reporting.ReportingStats.ApiKey" value="secret" />' to the app.config of the ReportingService."
#
#########################################################################

. ".\LoadFunctions.ps1"

Add-Type -AssemblyName System.Web

#$Config = 			GetConfig

$ServerName = 		$(Hostname).ToUpper()

$CustomerId			= GetConfigValue "customerid"
$planolog			= GetConfigValue "paths.planolog"
$statusurisecret	= GetConfigValue "reporting.statusurisecret"
$statusurisecret	= [System.Web.HttpUtility]::UrlEncode($statusurisecret)
$statusuri			= GetConfigValue "reporting.statusuri"
$targetpath			= "${planolog}\reportingstats"
$completeuri		= "${statusuri}${statusurisecret}"

#Scriptname for logging
$scriptname = "CollectData_ReportingStats.ps1" 
$scriptversion = "2023-07-25 15:43"

###########################################################################
#
mkdir $targetpath -Force > $null
$datestring = (Get-Date).tostring("yyyyMMdd-HHmm")
$targetfile = "${targetpath}\${customerid}_${servername}_reportingstats_${datestring}.log"

if($null -eq $completeuri -or $completeuri.Length -lt 5){
	"Error: status url too short or empty. Please check configuration."
	exit 1
}
else{
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
	}
}
