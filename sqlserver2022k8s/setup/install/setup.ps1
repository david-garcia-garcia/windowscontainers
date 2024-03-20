$global:ErrorActionPreference = 'Stop'

Start-Service 'MSSQLSERVER';

# https://github.com/dataplat/dbatools/pull/9252
# Install https://ola.hallengren.com/
Write-Host "`n---------------------------------------"
Write-Host " Install https://ola.hallengren.com/"
Write-Host "-----------------------------------------`n"

Install-DbaMaintenanceSolution -SqlInstance "localhost" -LogToTable;

choco install azcopy10 -y --no-progress;

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;