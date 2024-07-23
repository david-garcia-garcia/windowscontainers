function SbsRestoreDatabase {
    param(
        [Parameter(Mandatory = $true)]
        [DbaInstanceParameter]$SqlInstance,
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [Nullable[DateTime]]$RestoreTime
    )

    SbsWriteHost "Starting database restore...";

    $parsedUrl = SbsParseSasUrl -Url $Path;
    if ($null -ne $parsedUrl) {
        SbsEnsureCredentialForSasUrl -SqlInstance $sqlInstance -Url $Path;
    }

    $files = @();
    $files = SbsMssqlPrepareRestoreFiles -SqlInstance $sqlInstance -Path $Path -DatabaseName $databaseName;

    if ($null -eq $files -or $files.Count -eq 0) {
        SbsWriteWarning "No backup files found for database $databaseName. This might happen if this is the first time you spin up this instance.";
        return $false;
    }

    $files | Restore-DbaDatabase -SqlInstance $sqlInstance -DatabaseName $databaseName -EnableException -WithReplace -UseDestinationDefaultDirectories -ReplaceDbNameInFile -Verbose;
    
    $database = Get-DbaDatabase -SqlInstance $sqlInstance -Database $databaseName;
    
    if (-not $database) {
        SbsWriteError "Database $($databaseName) was not restored successfully."
        return $false;
    }
 
    SbsWriteHost "Database $($databaseName) restored successfully."

    Repair-DbaDbOrphanUser -SqlInstance $SqlInstance -Database $databaseName -RemoveNotExisting -Confirm:$false;

    return $true
}