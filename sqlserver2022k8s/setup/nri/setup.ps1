$global:ErrorActionPreference = 'Stop'

choco install newrelic-mssql -y --no-progress;

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;