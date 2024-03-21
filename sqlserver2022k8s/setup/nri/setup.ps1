$global:ErrorActionPreference = 'Stop'

choco install newrelic-mssql -y --version=2.12.0 --no-progress;

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;