$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Gather all environment variables that match the pattern SBS_CRON_TRIGGER_
$logins = Get-ChildItem env: | Where-Object { $_.Name -match '^MSSQL_LOGIN_(.*)$' }

Import-Module dbatools;

$errors = New-Object -TypeName System.Collections.ArrayList;

# Loop through each found environment variable
foreach ($login in $logins) {
    try {
        SbsWriteDebug "Adding Login"
        SbsMssqlAddLogin -instanceName "localhost" -LoginConfiguration $login.Value;
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