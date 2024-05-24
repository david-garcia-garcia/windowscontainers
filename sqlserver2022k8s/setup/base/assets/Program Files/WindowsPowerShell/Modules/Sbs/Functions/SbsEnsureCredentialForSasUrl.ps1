# Function to check and create or update the credential
function SbsEnsureCredentialForSasUrl {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter] $SqlInstance
    )

    $parsedUrl = sbsParseSasUrl -Url $Url;
    
    if ($null -eq $parsedUrl) {
        SbsWriteError "Invalid SAS URL";
        return;
    }

    if (($null -ne $parsedUrl.signedExpiry) -and ($parsedUrl.signedExpiry -lt (Get-Date))) {
        SbsWriteWarning "The SAS URL for $($parsedUrl.baseUrl) expired at $($parsedUrl.signedExpiry)";
        return;
    }

    if (($null -ne $parsedUrl.startTime) -and ($parsedUrl.startTime -gt (Get-Date))) {
        SbsWriteWarning "The SAS URL for $($parsedUrl.baseUrl) is not valid until $($parsedUrl.startTime)";
        return;
    }

    $expiryThreshold = (Get-Date).AddHours(72)
    if ($null -ne $parsedUrl.signedExpiry -and $parsedUrl.signedExpiry -lt $expiryThreshold) {
        SbsWriteWarning "The SAS URL for $($parsedUrl.baseUrl) will expire in the next 72 hours."
    }

    SbsEnsureSqlCredential -SqlInstance $SqlInstance -CredentialName $parsedUrl.baseUrl -SasToken $parsedUrl.sasToken;
}