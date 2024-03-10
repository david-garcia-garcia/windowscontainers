function SbsWriteHost {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Source = "SbsContainer",
        [string]$LogName = "Application"
    )

    Write-Host $message;
    Write-EventLog -LogName $LogName -Source $Source -EntryType Information -EventId 1 -Message $message;
}