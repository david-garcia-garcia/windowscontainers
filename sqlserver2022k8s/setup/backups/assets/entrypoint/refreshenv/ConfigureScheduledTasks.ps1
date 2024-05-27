$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Gather all environment variables that match the pattern SBS_CRON_TRIGGER_
$triggerEnvVars = Get-ChildItem env: | Where-Object { $_.Name -match '^MSSQL_JOB_(.*)$' }

Import-Module dbatools;

$sqlInstance = Connect-DbaInstance "localhost";

# Loop through each found environment variable
foreach ($var in $triggerEnvVars) {

    # Extract the JSON trigger configuration from the environment variable value
    $jsonTrigger = $var.Value;

    try {
        Set-SqlServerJobSchedule -SQLIntance $sqlInstance  -JsonTrigger $jsonTrigger;
    }
    catch {
        SbsWriteError "$($_.Message)";
    }
}