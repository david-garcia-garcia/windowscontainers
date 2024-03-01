########################################################
# Starts a background task that monitors backup and restore
# operations, logging progress to the event log.
# This is crucial to monitor long lasting operations
# that affect a container startup or tear-down.
########################################################

$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# SQL query to monitor backup and restore operations
$sqlQuery = @"
SELECT r.session_id AS [Session_Id],
       r.command AS [command],
       CONVERT(NUMERIC(6, 2), r.percent_complete) AS [% Complete],
       GETDATE() AS [Current Time],
       CONVERT(VARCHAR(20), DATEADD(ms, r.estimated_completion_time, GetDate()), 20) AS [Estimated Completion Time],
       CONVERT(NUMERIC(32, 2), r.total_elapsed_time / 1000.0 / 60.0) AS [Elapsed Min],
       CONVERT(NUMERIC(32, 2), r.estimated_completion_time / 1000.0 / 60.0) AS [Estimated Min],
       CONVERT(NUMERIC(32, 2), r.estimated_completion_time / 1000.0 / 60.0 / 60.0) AS [Estimated Hours],
       CONVERT(VARCHAR(1000), (
            SELECT SUBSTRING(TEXT, r.statement_start_offset / 2, CASE 
                        WHEN r.statement_end_offset = - 1
                            THEN 1000
                        ELSE (r.statement_end_offset - r.statement_start_offset) / 2
                        END) 
            FROM sys.dm_exec_sql_text(sql_handle)
       )) AS [Statement Text]
FROM sys.dm_exec_requests r
WHERE command LIKE 'RESTORE%'
OR    command LIKE 'BACKUP%'
"@

$sqlInstanceName = "localhost";
$database = "master";

# Start the background job
Start-Job -ScriptBlock {
    param($sqlInstanceName, $database, $sqlQuery)
    Import-Module dbatools;
    $sqlInstance = Connect-DbaInstance -SqlInstance localhost;
    while ($true) {
        $result = Invoke-DbaQuery -SqlInstance $sqlInstance -Database $database -Query $sqlQuery;
        if ($result) {
            foreach ($row in $result) {
                # Initialize an empty array to hold the column-value pairs for the current row
                $messageParts = @();
                # Iterate through each property (column) of the row
                foreach ($property in $row.PSObject.Properties) {
                    # Construct a string "ColumnName: Value" for each property
                    $messagePart = "$($property.Name): $($property.Value)"
                    # Add the constructed string to the messageParts array
                    $messageParts += $messagePart
                }
                # Join all the column-value pairs with a semicolon and a space
                $message = $messageParts -join "; "
                # Write the message to the Event Log
                Write-EventLog -LogName 'Application' -Source 'MSSQL_MANAGEMENT' -EntryType Information -EventId 1 `
                -Message $message;
            }
        }
        Start-Sleep -Seconds 8;
    }
} -ArgumentList $sqlInstanceName, $database, $sqlQuery