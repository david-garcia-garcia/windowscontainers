$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Iterate through environment variables that start with CREATEDIR_
Get-ChildItem env: | Where-Object { $_.Name -like "CREATEDIR_*" } | ForEach-Object {
    $envVar = $_
    $dirPath = $envVar.Value
    
    if (-not [string]::IsNullOrWhiteSpace($dirPath)) {
        # Check if the directory exists
        if (-not (Test-Path $dirPath)) {
            SbsWriteDebug "Creating directory: $dirPath"
            try {
                New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
                SbsWriteDebug "Successfully created directory: $dirPath"
            } catch {
                SbsWriteHost "Failed to create directory $dirPath - $($_.Exception.Message)"
            }
        } else {
            SbsWriteDebug "Directory already exists: $dirPath, skipping creation"
        }
    } else {
        SbsWriteHost "Invalid or empty path for $($envVar.Name)"
    }
}

SbsWriteDebug "Directory creation completed."