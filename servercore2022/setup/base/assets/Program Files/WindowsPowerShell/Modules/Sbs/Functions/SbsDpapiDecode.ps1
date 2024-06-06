function SbsDpapiDecode {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $EncodedValue
    )

    Add-Type -AssemblyName System.Security;
    $bytes = [Convert]::FromBase64String($EncodedValue);
    return [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, 'LocalMachine'));
}