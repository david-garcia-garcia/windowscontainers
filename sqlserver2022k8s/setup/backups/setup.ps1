$global:ErrorActionPreference = 'Stop'

Start-Service 'MSSQLSERVER';

# https://github.com/dataplat/dbatools/pull/9252
# Install https://ola.hallengren.com/
Write-Host "Install https://ola.hallengren.com/";
Install-DbaMaintenanceSolution -SqlInstance "localhost" -LogToTable;