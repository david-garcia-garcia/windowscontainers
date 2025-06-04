$global:ErrorActionPreference = 'Stop'

Import-Module Sbs;

################################################
# Create local admin
################################################
$securePassword = ConvertTo-SecureString (SbsRandomPassword 20) -AsPlainText -Force;
New-LocalUser -Name "localadmin" -Password $securePassword -PasswordNeverExpires;
Add-LocalGroupMember -Group "Administrators" -Member "localadmin";

Write-Host "Created localadmin user";

################################################
# Disable software protection service
################################################
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\sppsvc" -Name "Start" -Value 4
Get-ScheduledTask -TaskPath "\Microsoft\Windows\SoftwareProtectionPlatform\" | Disable-ScheduledTask

################################################
# Cleanup
################################################
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;