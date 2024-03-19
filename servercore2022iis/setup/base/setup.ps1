$global:ErrorActionPreference = 'Stop'
$mypath = Split-Path $MyInvocation.MyCommand.Path

# Para el CCS del IIS, el polling interval de defecto son 300s. Lo ponemos a 90 (1.5 min).
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\IIS\CentralCertProvider" -Name "PollingInterval" -Value 90;

################################################
# Disable unsafe cyphers
################################################
$regFilePath = "${mypath}\iis_setup_templates\cypher.reg";
Write-Host "`n---------------------------------------"
Write-Host " Disabling unsafe cyphers system wide ($regFilePath)"
Write-Host "-----------------------------------------`n"
reg import $regFilePath;

################################################
# Disable default pool
################################################

Write-Host "`n---------------------------------------"
Write-Host " Configurating default application pool"
Write-Host "-----------------------------------------`n"

Stop-WebAppPool -Name "DefaultAppPool";
Import-Module WebAdministration;
$ApplicationPoolName = "IIS:\AppPools\DefaultAppPool";
$AppPool = Get-Item $ApplicationPoolName;
$AppPool.autoStart = 'false';
$AppPool.startmode = 'alwaysrunning';
$AppPool | Set-Item;

################################################
# IIS remote management
################################################

Write-Host "`n---------------------------------------"
Write-Host " Deploying IIS remote management"
Write-Host "-----------------------------------------`n"

# https://mcpmag.com/articles/2014/10/21/enabling-iis-remote-management.aspx
Install-WindowsFeature  Web-Mgmt-Service;
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WebManagement\Server" -Name "EnableRemoteManagement" -Value 1;
Set-Service -name WMSVC -StartupType Manual;
Write-Host "IIS Remote Management enabled";

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;