function global:SbsFilteredEventLog {
    param (
        [DateTime]$After,
        [array]$Configurations,
        $ValidProviders
    )

    # Create a new collection to hold the remapped configurations as hashtables
    $remappedConfigurations = @()

    foreach ($config in $Configurations) {
        $ht = @{}
        foreach ($prop in $config.PSObject.Properties) {
            $ht[$prop.Name] = $prop.Value
        }
        $ht['StartTime'] = $After

        if ($ht['ProviderName'] -eq '*') {
            $ht['ProviderName'] = $ValidProviders;
        }

        $remappedConfigurations += $ht
    }

    # Write-Host ($remappedConfigurations | ConvertTo-Json -Depth 5);

    $events = Get-WinEvent -ErrorAction SilentlyContinue -FilterHashtable $remappedConfigurations -Force;

    foreach ($message in $events) {
        $formattedMessage = "[{0}] [{2}: {1}] {3}" -f $message.TimeCreated.ToString("HH:mm:ss"), $message.ProviderName, $message.LevelDisplayName, $message.Message
        Write-Output $formattedMessage
    }
}