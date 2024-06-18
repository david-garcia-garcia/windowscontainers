########################################
# Set ADMIN account
########################################
SbsWriteHost "Configuring admin account";
Add-Type -AssemblyName System.Security;
$password = SbsDpapiDecode -EncodedValue $Env:MSSQL_ADMIN_PWD;
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force;
Set-DbaLogin -SqlInstance "localhost" -Login $Env:MSSQL_ADMIN_USERNAME -SecurePassword $securePassword -Enable -GrantLogin -PasswordPolicyEnforced:$false -Force -Confirm:$false | Out-Null;