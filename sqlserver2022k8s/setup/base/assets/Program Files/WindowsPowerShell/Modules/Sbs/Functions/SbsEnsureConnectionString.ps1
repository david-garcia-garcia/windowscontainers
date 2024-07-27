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

        #Data Source=localhost;Integrated Security=True;Multiple Active Result
        #Sets=False;Encrypt=True;Trust Server Certificate=True;Packet Size=4096;Application
        #Name="dbatools PowerShell module - dbatools.io"

        $connectionString = $sqlInstance.ConnectionContext.ConnectionString;

        # For whatever reason, the format of some properties in this connection string
        # need to be fixed.
        $connectionString = $connectionString -replace "Trust Server Certificate=", ";TrustServerCertificate="
        $connectionString = $connectionString -replace "Multiple Active Result Sets=", ";MultipleActiveResultSets="
        return $connectionString;
    }
}