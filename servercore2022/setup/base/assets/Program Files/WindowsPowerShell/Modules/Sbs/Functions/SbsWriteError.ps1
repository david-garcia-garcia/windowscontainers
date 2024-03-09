function SbsWriteError {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Source = "SbsContainer",
        [string]$LogName = "Application"
    )

    Write-Error $message;
    Write-EventLog -LogName $LogName -Source $Source -EntryType Error -EventId 1 -Message $message;
}