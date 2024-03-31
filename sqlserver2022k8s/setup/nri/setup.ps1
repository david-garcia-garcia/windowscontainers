$global:ErrorActionPreference = 'Stop'

$url = "https://github.com/newrelic/nri-mssql/releases/download/v2.12.0/nri-mssql-386.2.12.0.zip";

SbsDownloadFile -Url $url -Path "$env:TEMP\nri-mssql.zip";
Expand-Archive -Path "$env:TEMP\nri-mssql.zip" -DestinationPath "C:\Program Files\" -Force

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;