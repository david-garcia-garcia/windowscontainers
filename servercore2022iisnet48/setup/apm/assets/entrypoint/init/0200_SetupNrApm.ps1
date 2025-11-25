. "c:\entrypoint\refreshenv\SetupNrApm.ps1";

# Check if New Relic APM should be configured for IIS services
if (SbsGetEnvBool "SETUP_IIS_NR_APM") {
    SbsWriteHost "Configuring New Relic APM for IIS services"

    # https://github.com/DataDog/dd-trace-dotnet/issues/343
    # https://github.com/DataDog/dd-trace-dotnet/blob/12926d187c16467d5c60e36d28b9c3fa6398c28a/deploy/Datadog.Trace.ClrProfiler.WindowsInstaller/Product.wxs#L148-L150

    # Environment variables to copy from BACKUP_* to service registry
    $envVarsToCopy = @(
        "COR_ENABLE_PROFILING",
        "COR_PROFILER",
        "CORECLR_NEWRELIC_HOME",
        "CORECLR_PROFILER"
    )

    # Copy environment variables from BACKUP_* to W3SVC and WAS services
    $services = @("W3SVC", "WAS")
    foreach ($serviceName in $services) {
        $serviceEnvPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName\Environment"
        if (-not (Test-Path $serviceEnvPath)) {
            New-Item -Path $serviceEnvPath -Force | Out-Null
            SbsWriteHost "Created $serviceName Environment registry key"
        }

        foreach ($varName in $envVarsToCopy) {
            $backupName = "BACKUP_$varName"
            $backupValue = [System.Environment]::GetEnvironmentVariable($backupName, "Machine")
            
            if ($null -ne $backupValue -and $backupValue -ne "") {
                Set-ItemProperty -Path $serviceEnvPath -Name $varName -Value $backupValue -Type String
                SbsWriteHost "Set $varName=$backupValue for $serviceName service"
            }
        }
    }
} else {
    SbsWriteHost "SETUP_IIS_NR_APM is not enabled. Skipping New Relic APM configuration for IIS services."
}
