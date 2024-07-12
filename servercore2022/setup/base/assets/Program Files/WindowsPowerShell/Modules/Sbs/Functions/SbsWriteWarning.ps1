function SbsWriteWarning {
    param (
        [string]$Message,
        [string]$Source = "SbsContainer",
        [string]$LogName = "Application"
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return;
    }

    Write-Warning "[$(Get-Date -Format 'HH:mm:ss')] [Entrypoint] Warning $($message)"
    Write-EventLog -LogName $LogName -Source $Source -EntryType Warning -EventId 1 -Message $message;
}