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
        SbsWriteWarning "Invalid SAS URL";
    }

    SbsEnsureSqlCredential -SqlInstance $SqlInstance -CredentialName $parsedUrl.baseUrl -SasToken $parsedUrl.sasToken;
}