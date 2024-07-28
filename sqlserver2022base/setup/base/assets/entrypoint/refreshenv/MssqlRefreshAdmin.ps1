########################################
# Set ADMIN account
########################################
SbsWriteHost -Message "Configuring admin account";
$password = SbsDpapiDecode -EncodedValue $Env:MSSQL_ADMIN_PWD;
$userName = SbsGetEnvString "MSSQL_ADMIN_USERNAME"
if ([string]::IsNullOrWhiteSpace($password) -or [string]::IsNullOrWhiteSpace($userName)) {
    SbsWriteError "No username or password provided for admin account. Use MSSQL_ADMIN_USERNAME and MSSQL_ADMIN_PWD to provide an administrator account.";
}
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force;
Set-DbaLogin -SqlInstance "localhost" -Login $userName -SecurePassword $securePassword -Enable -GrantLogin -PasswordPolicyEnforced:$false -Force -Confirm:$false -EnableException | Out-Null;