$global:ErrorActionPreference = 'Stop';

Write-Host "`n---------------------------------------"
Write-Host " New Relic Perfmon Integration Setup"
Write-Host "-----------------------------------------`n"

$mypath = $MyInvocation.MyCommand.Path
$mypath = Split-Path $mypath -Parent

$serviceName = 'newrelic-infra';
$service = Get-Service | Where-Object {$_.Name -like $serviceName };

if ($service.Length -eq 0) {
	throw "This script needs the New Relic Infrastructure service to be already deployed.";
}

# Instalar monitorización con PERFMON, sin monitorizar nada. Para el servicio
# por si ya estuviera instalado

Write-Host "`n---------------------------------------"
Write-Host " Stopping New Relic Infrastructure agent... "
Write-Host "-----------------------------------------`n"
Set-Service -Name $serviceName -StartupType Manual;
Stop-Service -Name $serviceName;

Write-Host "`n---------------------------------------"
Write-Host " Downloading integration agent"
Write-Host "-----------------------------------------`n"

$tempExtracted = 'c:\windows\temp\nri-perfmon';

# Hay un BUG en NRI https://github.com/newrelic/nri-perfmon/pull/46 hasta que esté resuelto
# tiramos de una compilación custom del NRI-PERFMON
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
(New-Object Net.WebClient).DownloadFile('https://github.com/newrelic/nri-perfmon/releases/download/0.6.2/nri-perfmon-release-x64.zip','c:\windows\temp\nri-perfmon-release-x64.zip');
7z x "c:\windows\temp\nri-perfmon-release-x64.zip" -o"$tempExtracted" -aoa

# The installation script only works when CDd to the setup directory
Set-Location $tempExtracted
.\install-windows.ps1

# Restaurar el CWD
Set-Location  $mypath

Remove-item $tempExtracted -Force -Recurse

# Borramos las configuraciones de defecto para que no monitorice nada.
Remove-Item "C:\Program Files\New Relic\newrelic-infra\custom-integrations\nri-perfmon-definition.yml";
Remove-Item "C:\Program Files\New Relic\newrelic-infra\custom-integrations\nri-perfmon\config.json";

Write-Host "`n---------------------------------------"
Write-Host " Stopping New Relic Infrastructure agent... "
Write-Host "-----------------------------------------`n"
Stop-Service -Name $serviceName;
Set-Service -Name $serviceName -StartupType Disabled;

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;