$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

$SBS_LOCALADMIN_ENCODED = [System.Environment]::GetEnvironmentVariable("SBS_LOCALADMINPWD");
$SBS_LOCALADMINPWD = SbsDpapiDecode -EncodedValue $SBS_LOCALADMIN_ENCODED

if (-not [string]::IsNullOrWhiteSpace($SBS_LOCALADMINPWD)) {
    SbsWriteDebug -Message "Setting password to localadmin account"
    net user localadmin $SBS_LOCALADMINPWD;
}
