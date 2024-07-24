$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Gather all environment variables that match the pattern SBS_CRON_TRIGGER_
$jobs = Get-ChildItem env: | Where-Object { $_.Name -match '^MSSQL_JOB_(.*)$' }

Import-Module dbatools;

$sqlInstance = Connect-DbaInstance "localhost";

$MSSQL_AGENT_ENABLED = SbsGetEnvBool "MSSQL_AGENT_ENABLED"

if ($MSSQL_AGENT_ENABLED -eq $false) {
    SbsWriteWarning "MSSQL jobs have been configured through environment, but the MSSQL Server Agent is not enabled through MSSQL_AGENT_ENABLED";
}

# Loop through each found environment variable
foreach ($job in $jobs) {
    Set-SqlServerJob -SQLInstance $sqlInstance -JobDefinition $job.Value;
}