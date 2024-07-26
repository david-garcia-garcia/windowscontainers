$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Gather all environment variables that match the pattern SBS_CRON_TRIGGER_
$logins = Get-ChildItem env: | Where-Object { $_.Name -match '^MSSQL_LOGIN_(.*)$' }

Import-Module dbatools;

# Loop through each found environment variable
foreach ($login in $logins) {
    if ([string]::IsNullOrWhiteSpace($login.Value)) {
        SbsWriteError "Empty config for login $($login.Name)";
        continue;
    }
    SbsWriteDebug "Adding Login $($login.Name)"
    SbsMssqlAddLogin -instance "localhost" -LoginConfiguration $login.Value;
}