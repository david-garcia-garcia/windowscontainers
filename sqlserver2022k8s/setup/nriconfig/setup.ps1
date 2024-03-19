$global:ErrorActionPreference = 'Stop'

Start-Service 'MSSQLSERVER';

Import-Module Sbs;

#########################################
# Configure a DatabaseBackupInfoTable that we
# can use from within NRI to consolidate metrics
# about database backup state
#########################################
SbsDeployDbBackupInfo "localhost";

Write-Host "`n---------------------------------------"
Write-Host " Registering Scheduled Tasks"
Write-Host "-----------------------------------------`n"

Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\DeployMssqlNri.xml" -Raw) -TaskName "DeployMssqlNri";

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;