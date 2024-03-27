#################################################
# This script applies basic server settings 
# and starts the server
#################################################

$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

$needsRestart = $false;

Start-Service 'MSSQLSERVER';
$sqlInstance = Connect-DbaInstance -SqlInstance "localhost";

# Define default settings
$defaultSettings = @{
    "max degree of parallelism"  = 1
    "backup compression default" = 1
}

# Read the environment variable
$envSettings = $Env:MSSQL_SPCONFIGURE;

# Parse the environment variable settings
$parsedEnvSettings = @{}
if ($null -ne $envSettings) {
    $settingsArray = $envSettings.Split(';')
    foreach ($setting in $settingsArray) {
        if (-not [String]::IsNullOrWhiteSpace($setting)) {
            $splitSetting = $setting.Split(':');
            $parsedEnvSettings[$splitSetting[0].Trim()] = $splitSetting[1].Trim();
        }
    }
}

$finalSettings = $defaultSettings.Clone();
foreach ($key in $parsedEnvSettings.Keys) {
    $finalSettings[$key] = $parsedEnvSettings[$key];
}

# Apply the settings
foreach ($key in $finalSettings.Keys) {
    $currentConfig = Get-DbaSpConfigure -SqlInstance $sqlInstance -Name $key;
    $isDynamic = $currentConfig.IsDynamic; # If dynamic, the server does NOT need a restart after the change.
    $currentValue = $currentConfig.ConfiguredValue;
    $newValue = $finalSettings[$key];
    if ($newValue -ne $currentValue) {
        Set-DbaSpConfigure -SqlInstance $sqlInstance -Name $key -Value $newValue;
        SbsWriteHost "SPCONFIGURE SET '$key' to '$newValue' from '$currentValue' with isDymamic '$isDynamic'";
        if ($true -eq $isDynamic) {
            $needsRestart = $true;
        }
    }
}

$maxMemory = SbsGetEnvInt -name "MSSQL_MAXMEMORY" -defaultValue $null;
if (($null -ne $maxMemory)) {
    if ($maxMemory -gt 280) {
        SbsWriteHost "Setting max memory to $($maxMemory)Mb";
        Set-DbaMaxMemory -SqlInstance $sqlInstance -Max $maxMemory;
    }
    else {
        SbsWriteHost "Max memory is less than 280MB, not setting."
    }
}

$minMemory = SbsGetEnvInt -name "MSSQL_MINMEMORY" -defaultValue $null;
if (($null -ne $minMemory)) {
    if ($minMemory -gt 256) {
        SbsWriteHost "Setting min memory to $($minMemory)Mb";
        Set-DbaSpConfigure -SqlInstance $sqlInstance -Name "min server memory" -Value $minMemory;
    }
    else {
        SbsWriteHost "Min memory is less than 256MB, not setting."
    }
}

if (($true -eq $needsRestart) -or ($Env:MSSQL_SPCONFIGURERESTART -eq '1')) {
    SbsWriteHost "Server post config restart.";
    Restart-DbaService -ComputerName "localhost";
}

# Check timeouts - in K8S use lifecycle hooks
if ($null -eq $Env:MSSQL_DISABLESHUTDOWNTIMEOUTCHECK) {
    $timeout = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\cexecsvc").ProcessShutdownTimeoutSeconds;
    $minimium = 20;
    if (($Env:MSSQL_LIFECYCLE -eq "BACKUP") -or ($Env:MSSQL_AUTOBACKUP -eq "1")) {
        $minimium = 60;
    }
    if ($timeout -lt $minimium) {
        Write-Error "Current shutdown timeout of $($timeout)s is lower than the minimum of $($minimium)s for this workload. Use SBS_SHUTDOWNTIMEOUT to set a bigger timeout. If this is running in K8S, configure a LifeCycleHook for shutdown instead of increasing the timeout and set the MSSQL_DISABLESHUTDOWNTIMEOUTCHECK environment variable."
    }
}
