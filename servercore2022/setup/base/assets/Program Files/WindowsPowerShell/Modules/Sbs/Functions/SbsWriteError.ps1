function SbsWriteError {
    param (
        [string]$Message,
        [string]$Source = "SbsContainer",
        [string]$LogName = "Application"
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return;
    }
    
    Write-EventLog -LogName $LogName -Source $Source -EntryType Error -EventId 1 -Message $message;
    Write-Error "[$(Get-Date -Format 'HH:mm:ss')] [Entrypoint] Error $($message)"
}