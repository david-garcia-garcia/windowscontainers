$global:ErrorActionPreference = 'Stop'

Start-Service 'MSSQLSERVER';

# https://github.com/dataplat/dbatools/pull/9252
# Install https://ola.hallengren.com/
Write-Host "`n---------------------------------------"
Write-Host " Install https://ola.hallengren.com/"
Write-Host "-----------------------------------------`n"

Install-DbaMaintenanceSolution -SqlInstance "localhost" -LogToTable -InstallJobs;

Write-Host "`n---------------------------------------"
Write-Host " Install https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit"
Write-Host "-----------------------------------------`n"

Install-DbaFirstResponderKit -SqlInstance "localhost"

# Disable jobs that we will not be using (backups are taken care of differently)
$JobsToDisable = @(
    "DatabaseBackup - SYSTEM_DATABASES - FULL",
    "DatabaseBackup - USER_DATABASES - DIFF",
    "DatabaseBackup - USER_DATABASES - FULL",
    "DatabaseBackup - USER_DATABASES - LOG",
    "DatabaseIntegrityCheck - SYSTEM_DATABASES",
    "DatabaseIntegrityCheck - USER_DATABASES"
)

foreach ($JobName in $JobsToDisable) {
    Set-DbaAgentJob -SqlInstance "localhost" -Job $JobName -Disabled;
}

Write-Host "`n---------------------------------------"
Write-Host " Install azcopy"
Write-Host "-----------------------------------------`n"

choco install azcopy10 -y --version=10.25.1 --no-progress;

Write-Host "`n---------------------------------------"
Write-Host " Install Az.Storage"
Write-Host "-----------------------------------------`n"

Install-Module -Name Az.Storage -RequiredVersion 6.2.0 -Force;

# Cleanup
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;