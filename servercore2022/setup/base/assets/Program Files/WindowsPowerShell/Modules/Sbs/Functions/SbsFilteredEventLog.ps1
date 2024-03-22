function SbsFilteredEventLog {
    param (
        [DateTime]$After,
        [array]$Configurations
    )

    $allMessages = @()

    foreach ($config in $Configurations) {

        $logName = $config.LogName;
        $source = $config.Source;
        $minLevel = $config.MinLevel;

        if ([string]::IsNullOrWhiteSpace($logName)) {
            continue;
        }

        if ([string]::IsNullOrWhiteSpace($source)) {
            $source = "*"
        }

        if ($null -eq $minLevel) {
            $minLevel = "Information"
        }

        $events = Get-EventLog -LogName $logName -After $After -Source $source | Where-Object { $_.EntryType -ge $minLevel }
        $allMessages += $events
    }

    $sortedMessages = $allMessages | Sort-Object -Property TimeGenerated

    foreach ($message in $sortedMessages) {
        $formattedMessage = "[{0}] [{2}: {1}] {3}" -f $message.TimeGenerated.ToString("HH:mm:ss"), $message.Source, $message.EntryType, $message.Message
        Write-Output $formattedMessage
    }
}