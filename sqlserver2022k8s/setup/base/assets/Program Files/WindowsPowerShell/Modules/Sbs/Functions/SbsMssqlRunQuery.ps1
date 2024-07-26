<#
.SYNOPSIS
This is here to avoid using dbatools as much as possible. The problema
is that in a container, it takes 7s to Import, plus super high CPU usage
when doing so.

.DESCRIPTION
Long description

.PARAMETER Instance
Parameter description

.PARAMETER CommandText
Parameter description

.PARAMETER CommandType
Parameter description

.PARAMETER CommandTimeout
Parameter description

.PARAMETER Parameters
Parameter description

.EXAMPLE
An example

.NOTES
General notes
#>
function SbsMssqlRunQuery {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Instance,
        [Parameter(Mandatory = $true)]
        [string]$CommandText,
        [System.Data.CommandType]$CommandType = 'Text',
        [int]$CommandTimeout = 1800,
        [hashtable]$Parameters = $null
    )

    # This method is supposed to be flexible in terms of NOT relying on DBATOOLS to run
    # SQL Queries. $Instance can be a connection string, a dbatools server instance
    # or something simple such as "localhost" (just the server name.)
    $connectionString = SbsEnsureConnectionString -SqlInstanceOrConnectionString $Instance;

    $SqlConn = $null
    $results = @()

    Try {
        $SqlConn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $SqlConn.Open()
        $cmd = $SqlConn.CreateCommand()
        $cmd.CommandType = $CommandType
        $cmd.CommandText = $CommandText
        $cmd.CommandTimeout = $CommandTimeout

        if ($Parameters) {
            foreach ($key in $Parameters.Keys) {
                $cmd.Parameters.AddWithValue($key, $Parameters[$key]) | Out-Null
            }
        }

        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $row[$reader.GetName($i)] = $reader[$i]
            }
            $results += $row
        }
        $reader.Close()
    }
    Finally {
        if ($null -ne $SqlConn) {
            $SqlConn.Close()
            $SqlConn.Dispose()
        }
    }

    return $results;
}
