function SbsWriteWarning {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Source = "SbsContainer",
        [string]$LogName = "Application"
    )

    Write-Warning "[$(Get-Date -Format 'HH:mm:ss')] [Entrypoint] Warning $($message)"
    Write-EventLog -LogName $LogName -Source $Source -EntryType Warning -EventId 1 -Message $message;
}