# Function to check and create or update the credential
function SbsEnsureSqlCredential {
    param (
        [string]$SqlInstance,
        [string]$CredentialName,
        [string]$SasToken
    )

    $sqlQuery = @"
IF NOT EXISTS (SELECT * FROM sys.credentials WHERE name = '$CredentialName')
    CREATE CREDENTIAL [$CredentialName] WITH IDENTITY = 'SHARED ACCESS SIGNATURE', SECRET = '$SasToken';
ELSE
    ALTER CREDENTIAL [$CredentialName] WITH IDENTITY = 'SHARED ACCESS SIGNATURE', SECRET = '$SasToken';
"@

    Invoke-DbaQuery -SqlInstance $SqlInstance -Query $sqlQuery
    Write-Host "Credential '$CredentialName' upserted."
}