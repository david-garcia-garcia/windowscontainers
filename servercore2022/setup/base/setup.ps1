$global:ErrorActionPreference = 'Stop'

Import-Module Sbs;

################################################
# Create local admin
################################################
$securePassword = ConvertTo-SecureString (SbsRandomPassword 20) -AsPlainText -Force;
New-LocalUser -Name "localadmin" -Password $securePassword -PasswordNeverExpires;
Add-LocalGroupMember -Group "Administrators" -Member "localadmin";

Write-Host "Created localadmin user";