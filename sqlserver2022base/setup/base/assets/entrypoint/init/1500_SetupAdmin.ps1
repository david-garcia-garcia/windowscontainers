########################################
# Set ADMIN account
########################################
SbsWriteHost "Configuring admin account";
$securePassword = ConvertTo-SecureString $Env:MSSQL_ADMIN_PWD -AsPlainText -Force;
Set-DbaLogin -SqlInstance "localhost" -Login $Env:MSSQL_ADMIN_USERNAME -SecurePassword $securePassword -Enable -GrantLogin -PasswordPolicyEnforced:$false -Force -Confirm:$false