function SbsWriteHost {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Source = "SbsContainer",
        [string]$LogName = "Application"
    )

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [Entrypoint] Information $($message)"
    Write-EventLog -LogName $LogName -Source $Source -EntryType Information -EventId 1 -Message $message;
}