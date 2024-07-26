# Function to check and create or update the credential
function SbsEnsureSqlCredential {
    param (
        [object]$SqlInstance,
        [string]$CredentialName,
        [string]$SasToken
    )

    # Check if the CredentialName ends with "/"
    $CredentialName = $CredentialName.TrimEnd('/');

    $sqlQuery = @"
IF NOT EXISTS (SELECT * FROM sys.credentials WHERE name = '$CredentialName')
    CREATE CREDENTIAL [$CredentialName] WITH IDENTITY = 'SHARED ACCESS SIGNATURE', SECRET = '$SasToken';
ELSE
    ALTER CREDENTIAL [$CredentialName] WITH IDENTITY = 'SHARED ACCESS SIGNATURE', SECRET = '$SasToken';
"@
    SbsMssqlRunQuery -SqlInstance $SqlInstance -CommandText $sqlQuery
    Write-Host "Credential '$CredentialName' upserted."
}