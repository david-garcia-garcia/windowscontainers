function SbsWriteDebug {
    param (
        [string]$Message,
        [string]$Source = "SbsContainer",
        [string]$LogName = "Application"
    )

    if ((SbsGetEnvBool "SBS_DEBUG") -eq $false) {
        return;
    }

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return;
    }

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [Entrypoint] Debug $($message)"
    Write-EventLog -LogName $LogName -Source $Source -EntryType Information -EventId 1 -Message $message;
}