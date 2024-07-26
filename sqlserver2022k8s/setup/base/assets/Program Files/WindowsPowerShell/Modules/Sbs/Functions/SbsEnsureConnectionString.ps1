<#
.SYNOPSIS
Ensure that we have a connection string.

.DESCRIPTION
Get a connection string. If input is a dbatools connection object, it will be extracted,
if not, it might be interpreted as a connection string or a server name.

.PARAMETER SqlInstanceOrConnectionString
Parameter description

.EXAMPLE
An example

.NOTES
General notes
#>
function SbsEnsureConnectionString {

    [OutputType([String])]
    param (
        [object]$SqlInstanceOrConnectionString
    )

    # Server name
    if ($SqlInstanceOrConnectionString -is [String] -and -not($SqlInstanceOrConnectionString -match "=")) {
        return "Data Source=$SqlInstanceOrConnectionString;TrustServerCertificate=Yes;Integrated Security=True;"
    }

    # Connection string
    if ($SqlInstanceOrConnectionString -is [String]) {
        return $SqlInstanceOrConnectionString;
    }

    # Deal with a dbatools connection object
    if ($SqlInstanceOrConnectionString.PSobject.Properties.name -match "ConnectionContext") {
        $connectionStringBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
        $connectionStringBuilder['Data Source'] = $sqlInstance.ConnectionContext.ServerInstance
        $connectionStringBuilder['User ID'] = $sqlInstance.ConnectionContext.Login
        $connectionStringBuilder['Password'] = $sqlInstance.ConnectionContext.Password
        $connectionStringBuilder['Encrypt'] = $false
        $connectionStringBuilder['TrustServerCertificate'] = $sqlInstance.ConnectionContext.TrustServerCertificate
        return $connectionStringBuilder.ConnectionString
    }
}