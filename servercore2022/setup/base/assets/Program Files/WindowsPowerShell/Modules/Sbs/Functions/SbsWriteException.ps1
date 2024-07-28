function SbsWriteException {
    param (
        [object]$Exception,
        [string]$Source = "SbsContainer",
        [string]$LogName = "Application"
    )

    $message = '';

    if ($Exception -is [System.Management.Automation.ErrorRecord]) {
        $details = $Exception.ErrorDetails;
        if ($Exception.Exception) {
            $details += "[$($Exception.Exception.GetType().Name)] $($Exception.Exception.Message)";
        }
        $message = "$($details) At $($Exception.ScriptStackTrace)" -replace "`n"," " -replace "`r"," "
    }

    if ($Exception -is [System.Exception]) {
        $message = "$($Exception.GetType().Name) $($Exception.Message) At $($Exception.StackTrace)" -replace "`n"," " -replace "`r"," "
    }

    Write-EventLog -LogName $LogName -Source $Source -EntryType Error -EventId 1 -Message $message;
    Write-Error "[$(Get-Date -Format 'HH:mm:ss')] [Entrypoint] Error $($message)"
}