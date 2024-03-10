function SbsFilteredEventLog {
    param (
        [DateTime]$After,
        [string]$LogNames,
        [string]$Source = "*"
    )
    
    if ([string]::IsNullOrWhiteSpace($Source)) {
        $Source = "*";
    }

    # Split the LogNames string into an array based on comma separation
    $LogNameArray = $LogNames -split ","
    
    foreach ($LogName in $LogNameArray) {
        # Trim spaces that might be present around log names
        $LogName = $LogName.Trim();

        # Ensure the current log name is not empty
        if (-not [string]::IsNullOrWhiteSpace($LogName)) {
            Get-EventLog -LogName $LogName -Source $Source -After $After | Select-Object Source, LogName, TimeGenerated, EntryType, Message;
        }
    }
}