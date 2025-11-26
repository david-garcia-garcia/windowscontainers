. "c:\entrypoint\refreshenv\SetupNrApm.ps1";

# Check if IIS service environment should be restored from backup
if (SbsGetEnvBool "IIS_RESTORE_SERVICE_ENV") {
    SbsWriteHost "Restoring IIS service environment variables from backup"

    # https://github.com/DataDog/dd-trace-dotnet/issues/343
    # https://github.com/DataDog/dd-trace-dotnet/blob/12926d187c16467d5c60e36d28b9c3fa6398c28a/deploy/Datadog.Trace.ClrProfiler.WindowsInstaller/Product.wxs#L148-L150

    # Restore W3SVC Environment from backup
    $w3svcBackup = [System.Environment]::GetEnvironmentVariable("NR_IIS_BACKUP_W3SVC_ENVIRONMENT", "Machine")
    if (-not [string]::IsNullOrWhiteSpace($w3svcBackup)) {
        $w3svcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\W3SVC"
        if (Test-Path $w3svcPath) {
            $envArray = $w3svcBackup -split '\|'
            Set-ItemProperty -Path $w3svcPath -Name "Environment" -Value $envArray
            SbsWriteHost "Restored W3SVC Environment from backup: $w3svcBackup"
        }
    } else {
        SbsWriteHost "No W3SVC Environment backup found (NR_IIS_BACKUP_W3SVC_ENVIRONMENT)"
    }

    # Restore WAS Environment from backup
    $wasBackup = [System.Environment]::GetEnvironmentVariable("NR_IIS_BACKUP_WAS_ENVIRONMENT", "Machine")
    if (-not [string]::IsNullOrWhiteSpace($wasBackup)) {
        $wasPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WAS"
        if (Test-Path $wasPath) {
            $envArray = $wasBackup -split '\|'
            Set-ItemProperty -Path $wasPath -Name "Environment" -Value $envArray
            SbsWriteHost "Restored WAS Environment from backup: $wasBackup"
        }
    } else {
        SbsWriteHost "No WAS Environment backup found (NR_IIS_BACKUP_WAS_ENVIRONMENT)"
    }
} else {
    SbsWriteHost "IIS_RESTORE_SERVICE_ENV is not enabled. Skipping IIS service environment restore."
}
