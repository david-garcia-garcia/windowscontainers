$global:ErrorActionPreference = 'Stop'

Start-Service 'MSSQLSERVER';

Write-Host "`n---------------------------------------"
Write-Host " Install DbaTools"
Write-Host "-----------------------------------------`n"

choco install dbatools -y --version=2.7.7 --no-progress;
if ($LASTEXITCODE -ne 0) {
    throw "DbaTools installation failed with exit code $LASTEXITCODE"
}

# All DBA tools stuff is going to be interacting with local server, so
# these default's whould be good to go.
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register -EnableException
Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register -EnableException
Set-DbatoolsInsecureConnection -Scope SystemDefault

# https://github.com/dataplat/dbatools/pull/9252
# Install https://ola.hallengren.com/
Write-Host "`n---------------------------------------"
Write-Host " Install https://ola.hallengren.com/"
Write-Host "-----------------------------------------`n"

Install-DbaMaintenanceSolution -SqlInstance "localhost" -LogToTable -InstallJobs -EnableException;

Write-Host "`n---------------------------------------"
Write-Host " Install https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit"
Write-Host "-----------------------------------------`n"

Install-DbaFirstResponderKit -SqlInstance "localhost" -EnableException

Write-Host "`n---------------------------------------"
Write-Host " Install https://github.com/erikdarlingdata/DarlingData"
Write-Host "-----------------------------------------`n"

Install-DbaDarlingData -SqlInstance "localhost" -EnableException

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
    Set-DbaAgentJob -SqlInstance "localhost" -Job $JobName -Disabled -EnableException;
}

Write-Host "`n---------------------------------------"
Write-Host " Install Az.Storage"
Write-Host "-----------------------------------------`n"

Install-Module -Name Az.Storage -RequiredVersion 9.5.0 -Force;

Write-Host "`n---------------------------------------"
Write-Host " Install SqlPackage"
Write-Host "-----------------------------------------`n"

choco install sqlpackage -y --version=170.2.70 --no-progress;
if ($LASTEXITCODE -ne 0) {
    throw "SqlPackage installation failed with exit code $LASTEXITCODE"
}

# Cleanup
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;