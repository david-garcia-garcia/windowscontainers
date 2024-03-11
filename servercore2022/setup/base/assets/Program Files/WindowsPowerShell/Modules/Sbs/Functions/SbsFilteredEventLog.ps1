function SbsFilteredEventLog {
    param (
        [DateTime]$After,
        [string]$LogNames,
        [string]$Source = "*",
        [string]$MinLevel = "Information"
    )
    
    if ([string]::IsNullOrWhiteSpace($Source)) {
        $Source = "*";
    }

    # Define a mapping from level names to event log entry type numerical values
    $levelMap = @{
        "Information"  = 0;
        "Warning"      = 1;
        "Error"        = 2;
        "Critical"     = 2;
        "SuccessAudit" = 3;
        "FailureAudit" = 4;
    }

    # Default MinLevel to Information if not recognized
    if (-not $levelMap.ContainsKey($MinLevel)) {
        $MinLevel = "Information"
    }

    # Split the LogNames string into an array based on comma separation
    $LogNameArray = $LogNames -split ","
    
    foreach ($LogName in $LogNameArray) {
        # Trim spaces that might be present around log names
        $LogName = $LogName.Trim();

        # Ensure the current log name is not empty
        if (-not [string]::IsNullOrWhiteSpace($LogName)) {
            $events = Get-EventLog -LogName $LogName -Source $Source -After $After | Where-Object {
                $levelMap[$_.EntryType] -ge $minLevelValue
            }

            foreach ($event in $events) {
                $event | Select-Object Source, LogName, TimeGenerated, EntryType, Message
            }
        }
    }
}