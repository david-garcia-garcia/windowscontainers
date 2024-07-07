$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Gather all environment variables that match the pattern SBS_CRON_TRIGGER_
$jobs = Get-ChildItem env: | Where-Object { $_.Name -match '^MSSQL_JOB_(.*)$' }

Import-Module dbatools;

$sqlInstance = Connect-DbaInstance "localhost";

$errors = New-Object -TypeName System.Collections.ArrayList;

# Loop through each found environment variable
foreach ($job in $jobs) {
    try {
        Set-SqlServerJob -SQLInstance $sqlInstance -JobDefinition $job.Value;
    }
    catch {
        SbsWriteWarning $_.Message;
        $errors.Add($_);
    }
}

if ($errors.Length -gt 1) {
    throw [System.AggregateException]::new($errors);
}

if ($errors.Length -gt 0) {
    throw $errors[0];
}