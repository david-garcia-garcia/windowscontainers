$global:ErrorActionPreference = 'Stop';

# Install NewRelic .NET agent
Write-Host "`n---------------------------------------"
Write-Host " choco upgrade newrelic-dotnet"
Write-Host "-----------------------------------------`n"
choco upgrade newrelic-dotnet -y --version=10.47.0 --no-progress;

Write-Host "`n---------------------------------------"
Write-Host " Backing up New Relic environment variables"
Write-Host "-----------------------------------------`n"

# Backup environment variables set by New Relic installer by renaming them
# This prevents global profiler activation - users can configure them explicitly in Kubernetes
# or they can be autoconfigured during container startup only for the IIS service
$envVarsToBackup = @(
    "COR_ENABLE_PROFILING",
    "COR_PROFILER",
    "COR_PROFILER_PATH_32",
    "CORECLR_ENABLE_PROFILING",
    "CORECLR_NEWRELIC_HOME",
    "CORECLR_PROFILER",
    "CORECLR_PROFILER_PATH_32"
)

foreach ($varName in $envVarsToBackup) {
    $currentValue = [System.Environment]::GetEnvironmentVariable($varName, "Machine")
    if ($null -ne $currentValue -and $currentValue -ne "") {
        $backupName = "BACKUP_$varName"
        [System.Environment]::SetEnvironmentVariable($backupName, $currentValue, "Machine")
        [System.Environment]::SetEnvironmentVariable($varName, $null, "Machine")
        Write-Host "Backed up $varName to $backupName (value: $currentValue)"
    }
}

Write-Host "`n---------------------------------------"
Write-Host " Backing up and clearing IIS services registry Environment"
Write-Host "-----------------------------------------`n"

# Backup and clear W3SVC Environment registry value
$w3svcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\W3SVC"
if (Test-Path $w3svcPath) {
    $w3svcProps = Get-ItemProperty -Path $w3svcPath
    if ($w3svcProps.Environment) {
        # Backup the entire Environment value as a pipe-delimited string
        $backupValue = $w3svcProps.Environment -join "|"
        [System.Environment]::SetEnvironmentVariable("NR_IIS_BACKUP_W3SVC_ENVIRONMENT", $backupValue, "Machine")
        Write-Host "Backed up W3SVC Environment to NR_IIS_BACKUP_W3SVC_ENVIRONMENT"
        Write-Host "Value: $backupValue"
        
        # Clear the Environment property from W3SVC
        Remove-ItemProperty -Path $w3svcPath -Name "Environment"
        Write-Host "Cleared W3SVC Environment registry property"
    }
}

# Backup and clear WAS Environment registry value
$wasPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WAS"
if (Test-Path $wasPath) {
    $wasProps = Get-ItemProperty -Path $wasPath
    if ($wasProps.Environment) {
        # Backup the entire Environment value as a pipe-delimited string
        $backupValue = $wasProps.Environment -join "|"
        [System.Environment]::SetEnvironmentVariable("NR_IIS_BACKUP_WAS_ENVIRONMENT", $backupValue, "Machine")
        Write-Host "Backed up WAS Environment to NR_IIS_BACKUP_WAS_ENVIRONMENT"
        Write-Host "Value: $backupValue"
        
        # Clear the Environment property from WAS
        Remove-ItemProperty -Path $wasPath -Name "Environment"
        Write-Host "Cleared WAS Environment registry property"
    }
}

Write-Host "`n---------------------------------------"
Write-Host " Default to strong crypto for .NET Framework"
Write-Host "-----------------------------------------`n"

# https://docs.newrelic.com/docs/apm/agents/net-agent/troubleshooting/no-data-appears-after-disabling-tls-10/#strongcrypto
# Esto hace falta para que el framework utilice por defecto TLS en lugar de SSL
Set-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319" -Name "SchUseStrongCrypto" -Value 1 -Type DWord;
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" -Name "SchUseStrongCrypto" -Value 1 -Type DWord;

Write-Host "`n---------------------------------------"
Write-Host " Creating New Relic log directory"
Write-Host "-----------------------------------------`n"

New-Item -Path "C:\var\log\newrelic" -ItemType Directory -Force | Out-Null
Write-Host "Created C:\var\log\newrelic directory"

Write-Host "`n---------------------------------------"
Write-Host " Deploying New Relic logrotate configuration"
Write-Host "-----------------------------------------`n"

# Ensure logrotate directory exists
$logrotateDir = "C:\logrotate\log-rotate.d"
if (-not (Test-Path $logrotateDir)) {
    New-Item -Path $logrotateDir -ItemType Directory -Force | Out-Null
    Write-Host "Created $logrotateDir directory"
}

# Copy logrotate configuration
Copy-Item -Path "c:\setup\assets\logrotate\newrelic.conf" -Destination "$logrotateDir\newrelic.conf" -Force
Write-Host "Deployed New Relic logrotate configuration to $logrotateDir\newrelic.conf"

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;

