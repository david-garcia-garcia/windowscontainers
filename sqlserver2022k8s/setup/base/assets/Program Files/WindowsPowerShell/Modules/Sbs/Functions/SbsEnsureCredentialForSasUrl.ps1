# Function to check and create or update the credential
function SbsEnsureCredentialForSasUrl {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [parameter(Mandatory = $true)]
        [object] $SqlInstance
    )

    if ([string]::isNullOrWhiteSpace($Url)) {
        return;
    }

    $parsedUrl = sbsParseSasUrl -Url $Url;
    
    if ($null -eq $parsedUrl) {
        SbsWriteError "Invalid SAS URL";
        return;
    }

    if (($null -ne $parsedUrl.signedExpiry) -and ($parsedUrl.signedExpiry -lt (Get-Date))) {
        SbsWriteError "The SAS URL expired at $($parsedUrl.signedExpiry)";
        return;
    }

    if (($null -ne $parsedUrl.startTime) -and ($parsedUrl.startTime -gt (Get-Date))) {
        SbsWriteError "The SAS URL is not valid until $($parsedUrl.startTime)";
        return;
    }

    SbsEnsureSqlCredential -SqlInstance $SqlInstance -CredentialName $parsedUrl.baseUrl -SasToken $parsedUrl.sasToken;
}