function SbsFilteredEventLog {
    param (
        [DateTime]$After,
        [array]$Configurations
    )

    $events = @();
    
    foreach ($configuration in $Configurations) {

        $Source = $configuration.Source;
        $MinLevel = $configuration.MinLevel;
        $LogName = $configuration.LogName;

        if ([string]::IsNullOrWhiteSpace($Source)) {
            $Source = "*";
        }

        if ($null -eq $MinLevel) {
            $MinLevel = "Information";
        }

        # Ensure the current log name is not empty
        if (-not [string]::IsNullOrWhiteSpace($LogName)) {
            try {
                $events += (Get-EventLog -LogName $LogName -Source $Source -After $After -Newest 250 | Where-Object {
                        $_.EntryType -le $MinLevel
                    });
            }
            catch {
                # Very rare, but there can be errors reading the log (cleared while reading, flooded, etc.)
                SbsWriteDebug "Error retrieving events from log: $LogName";
                SbsWriteDebug $_.Exception.Message;
            }
        }
    }

    $sortedEvents = $events | Sort-Object -Property Index, TimeGenerated;

    foreach ($event in $sortedEvents) {
        $formattedMessage = "[{0}] [{4}:{1}] {2} {3}" -f $event.TimeGenerated.ToString("HH:mm:ss"), $event.Source, $event.EntryType, $event.Message, $LogName
        Write-Output $formattedMessage
    }
}