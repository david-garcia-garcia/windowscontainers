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
# Install winget
################################################
New-Item -ItemType Directory -Path "$env:TEMP\winget-cli" -Force
Invoke-WebRequest -Uri "https://github.com/microsoft/winget-cli/releases/download/v1.4.10173/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -OutFile "$env:TEMP\winget-cli\winget.zip"
Expand-Archive -LiteralPath "$env:TEMP\winget-cli\winget.zip" -DestinationPath "$env:TEMP\winget-cli" -Force
Move-Item -Path "$env:TEMP\winget-cli\AppInstaller_x64.msix" -Destination "$env:TEMP\winget-cli\AppInstaller_x64.zip"
Expand-Archive -LiteralPath "$env:TEMP\winget-cli\AppInstaller_x64.zip" -DestinationPath "$env:TEMP\winget-cli" -Force
New-Item -ItemType Directory -Path "C:\winget-cli" -Force
Move-Item -Path "$env:TEMP\winget-cli\winget.exe" -Destination "C:\winget-cli\winget.exe"
Move-Item -Path "$env:TEMP\winget-cli\resources.pri" -Destination "C:\winget-cli\resources.pri"

################################################
# Cleanup
################################################
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;