function SbsDpapiEncode {

    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]
        $ClearValue
    )

    if ([string]::IsNullOrWhiteSpace($ClearValue)) {
        return $ClearValue;
    }

    Add-Type -AssemblyName System.Security;
    return [System.Convert]::ToBase64String([System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes($ClearValue), $null, 'LocalMachine'));
}