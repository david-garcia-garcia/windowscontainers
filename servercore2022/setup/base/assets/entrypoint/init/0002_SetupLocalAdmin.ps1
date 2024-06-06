$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

$SBS_LOCALADMINPWD = [System.Environment]::GetEnvironmentVariable("SBS_LOCALADMINPWD");

if (-not [string]::IsNullOrWhiteSpace($SBS_LOCALADMINPWD)) {
    net user localadmin $SBS_LOCALADMINPWD;
}
