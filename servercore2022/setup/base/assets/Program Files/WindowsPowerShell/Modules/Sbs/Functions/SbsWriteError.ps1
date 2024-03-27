function SbsWriteError {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Source = "SbsContainer",
        [string]$LogName = "Application"
    )

    Write-Error "[$(Get-Date -Format 'HH:mm:ss')] [Entrypoint] Error $($message)"
    Write-EventLog -LogName $LogName -Source $Source -EntryType Error -EventId 1 -Message $message;
}