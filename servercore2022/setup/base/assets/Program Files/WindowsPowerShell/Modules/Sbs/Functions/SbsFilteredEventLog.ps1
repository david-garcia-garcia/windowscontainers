function SbsFilteredEventLog {
    param (
        [DateTime]$After,
        [array]$Configurations
    )
    
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
            $events = Get-EventLog -LogName $LogName -Source $Source -After $After -Newest 200 | Where-Object {
                $_.EntryType -le $MinLevel
            }

            foreach ($event in $events) {
                $formattedMessage = "[{0}] [{4}:{1}] {2} {3}" -f $event.TimeGenerated.ToString("HH:mm:ss"), $event.Source, $event.EntryType, $event.Message, $LogName
                Write-Output $formattedMessage
            }
        }
    }
}