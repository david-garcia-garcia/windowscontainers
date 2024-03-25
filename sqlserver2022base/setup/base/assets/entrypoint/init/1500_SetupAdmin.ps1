########################################
# Set ADMIN account
########################################
SbsWriteHost "Configuring admin account";
$password = [Convert]::FromBase64String($Env:MSSQL_ADMIN_PWD);
$password = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($password, $null, 'LocalMachine'));
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force;
Set-DbaLogin -SqlInstance "localhost" -Login $Env:MSSQL_ADMIN_USERNAME -SecurePassword $securePassword -Enable -GrantLogin -PasswordPolicyEnforced:$false -Force -Confirm:$false