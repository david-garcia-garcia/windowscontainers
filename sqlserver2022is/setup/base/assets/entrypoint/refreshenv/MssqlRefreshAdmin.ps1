########################################
# Set ADMIN account
########################################
SbsWriteHost "Configuring admin account";
Add-Type -AssemblyName System.Security;
$password = SbsDpapiDecode -EncodedValue $Env:MSSQL_SA_PASSWORD;
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force;
Set-DbaLogin -SqlInstance "localhost" -Login "sa" -SecurePassword $securePassword -Enable -GrantLogin -EnableException -PasswordPolicyEnforced:$false -Force -Confirm:$false;