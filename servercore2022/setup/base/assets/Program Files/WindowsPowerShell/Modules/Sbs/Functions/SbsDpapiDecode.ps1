function SbsDpapiDecode {

    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        $EncodedValue
    )

    if ([string]::IsNullOrWhiteSpace($EncodedValue)) {
        return $EncodedValue;
    }

    try {
        Add-Type -AssemblyName System.Security;
        $bytes = [Convert]::FromBase64String($EncodedValue);
        return [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, 'LocalMachine'));
    }
    catch {
        SbsWriteWarning "Unable to decode variable, passing on unencoded string."
        return $EncodedValue;
    }
}