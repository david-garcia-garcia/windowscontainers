function SbsWriteHost {
    param (
        [string]$Message,
        [string]$Source = "SbsContainer",
        [string]$LogName = "Application"
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return;
    }

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [Entrypoint] Information $($message)"
    Write-EventLog -LogName $LogName -Source $Source -EntryType Information -EventId 1 -Message $message;
}