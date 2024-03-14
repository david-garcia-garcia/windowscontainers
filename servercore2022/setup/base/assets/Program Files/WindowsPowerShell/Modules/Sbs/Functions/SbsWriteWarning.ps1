function SbsWriteWarning {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Source = "SbsContainer",
        [string]$LogName = "Application"
    )

    Write-Warning "[$(Get-Date -Format 'HH:mm:ss.fff')] $($message)"
    Write-EventLog -LogName $LogName -Source $Source -EntryType Warning -EventId 1 -Message $message;
}