########################################
# Set SA account password
########################################
SbsWriteHost -Message "Configuring SA administrator account";
$password = SbsDpapiDecode -EncodedValue $Env:MSSQL_SA_PASSWORD;

if (-not([string]::IsNullOrWhiteSpace($password))) {
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force;
    Set-DbaLogin -SqlInstance "localhost" -Login "sa" -SecurePassword $securePassword -Enable -GrantLogin -PasswordPolicyEnforced:$false -Force -Confirm:$false -EnableException | Out-Null;
}