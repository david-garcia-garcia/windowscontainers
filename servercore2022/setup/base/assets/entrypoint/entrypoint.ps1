$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

Import-Module Sbs;

SbsPrepareEnv;

$initStopwatch = [System.Diagnostics.Stopwatch]::StartNew();

#####################################
# Setting timezone hardcoded here
#####################################

$timezone = [Environment]::GetEnvironmentVariable("SBS_CONTAINERTIMEZONE")

# Check if the timezone value was retrieved
if (-not [string]::IsNullOrWhiteSpace($timezone)) {
    # Set the timezone
    Set-TimeZone -Id $timezone;
    SbsWriteHost "Timezone set to $timezone from SBS_CONTAINERTIMEZONE";
}
else {
    $timeZone = Get-TimeZone;
    SbsWriteHost "System Timezone: ${$timeZone.Id}";
}

#####################################
# Delete Readyness Probe
#####################################

if (Test-Path("c:\ready")) {
    SbsWriteHost "Deleting readyness probe.";
    Remove-Item -Path 'C:\ready' -Force;
}

##########################################################################
# Setup shutdown listeners. For docker. In K8S use LifeCycleHooks
##########################################################################

$code = @"
using System;
using System.Runtime.InteropServices;

public class ConsoleCtrlHandler {

    [DllImport("Kernel32")]
    public static extern bool SetConsoleCtrlHandler(HandlerRoutine Handler, bool Add);

    public delegate bool HandlerRoutine(CtrlTypes CtrlType);

    public enum CtrlTypes {
        CTRL_C_EVENT = 0,
        CTRL_BREAK_EVENT,
        CTRL_CLOSE_EVENT,
        CTRL_LOGOFF_EVENT = 5,
        CTRL_SHUTDOWN_EVENT
    }

    private static bool _shutdownRequested = false;
    private static bool _shutdownAllowed = true;

    private static System.Collections.Concurrent.ConcurrentDictionary<string, DateTime> _signals = new System.Collections.Concurrent.ConcurrentDictionary<string, DateTime>();

    public static void SetShutdownAllowed(bool allowed) {
        _shutdownAllowed = allowed;
    }

    public static System.Collections.Concurrent.ConcurrentDictionary<string, DateTime> GetSignals() {
        return _signals;
    }

    public static bool GetShutdownRequested() {
        return _shutdownRequested;
    }

    public static bool ConsoleCtrlCheck(CtrlTypes ctrlType) {
        _signals.TryAdd(Convert.ToString(ctrlType), System.DateTime.UtcNow);
        switch (ctrlType) {
            case CtrlTypes.CTRL_CLOSE_EVENT:
            case CtrlTypes.CTRL_SHUTDOWN_EVENT:
                _shutdownRequested = true;
                System.Diagnostics.Stopwatch stopwatch = System.Diagnostics.Stopwatch.StartNew();
                while (!_shutdownAllowed && stopwatch.Elapsed.TotalSeconds < 600) {
                    System.Threading.Thread.Sleep(1000);
                }
                return true;
            default:
                return true;
        } 
    }
}
"@

# Add the C# type to the current PowerShell session
Add-Type -TypeDefinition $code -ReferencedAssemblies @("System.Runtime.InteropServices", "System.Collections.Concurrent");

# Create a delegate for the handler method
$handler = [ConsoleCtrlHandler+HandlerRoutine]::CreateDelegate([ConsoleCtrlHandler+HandlerRoutine], [ConsoleCtrlHandler], "ConsoleCtrlCheck");

# Register the handler
[ConsoleCtrlHandler]::SetConsoleCtrlHandler($handler, $true);

##########################################################################
# Adjust the ENTRY POINT error preference.
# Preferred is Stop, because app/container might have inconsistent
# state. Continue should be used for debugging purposes only.
##########################################################################
$SBS_ENTRYPOINTERRORACTION = [System.Environment]::GetEnvironmentVariable("SBS_ENTRYPOINTERRORACTION");
if ([string]::IsNullOrWhiteSpace($SBS_ENTRYPOINTERRORACTION)) {
    $SBS_ENTRYPOINTERRORACTION = 'Stop';
}
$global:ErrorActionPreference = $SBS_ENTRYPOINTERRORACTION;
SbsWriteHost "Start Entry Point with error action preference $global:ErrorActionPreference";
if ($global:ErrorActionPreference -ne 'Stop') {
    SbsWriteHost "Entry point PS Error Action Preference is not set to STOP. This will effectively allow errors to go through. Use only for debugging purposes.";
}

##########################################################################
# Run entry point scripts
##########################################################################
$initScriptDirectory = "C:\entrypoint\init";
if (Test-Path -Path $initScriptDirectory) {
    if ($Env:SBS_INITASYNC -eq "True") {
        Write-Host "Async Initialization";
        # We run this asynchronously for multiple reasons:
        # * Any PS loaded modules directly in the entrypoint will be LOCKED. This is an issue for debugging/hot replacing.
        # * Entrypoint init scripts can load huge modules (i.e. dbatools that uses 200MB or memory). If we run them directly in the entrypoint, the memory is not released.
        # Doing this ASYNC is a little bit slower, but it pays off in some situations.
        $job = Start-Job -ScriptBlock {
            param ($iniDir)
            # Get all .ps1 files in the directory
            $scripts = Get-ChildItem -Path $iniDir -Filter *.ps1 | Sort-Object Name | Select-Object $_.FullName;
            Write-Host "Running init scripts: $($scripts.Count) found."
            $global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }
            Import-Module Sbs;
            foreach ($script in $scripts) {
                Write-Host "START init script: $($script.Name)";
                & $script.FullName;
                Write-Host "END init script: $($script.Name)";
            }
        } -ArgumentList $initScriptDirectory

        Receive-Job -Job $job -Wait -AutoRemoveJob;

        # Check if the state is 'Failed' or if there are error records in the results
        if ($job.State -eq 'Failed') {
            SbsWriteHost "[$(Get-Date -format 'HH:mm:ss')] Task encountered an error during execution";
            $host.SetShouldExit(1);
            throw "Task $jobName failed";
        }
    }
    else {
        Write-Host "Sync Initialization";
        $scripts = Get-ChildItem -Path $initScriptDirectory -Filter *.ps1 | Sort-Object Name | Select-Object $_.FullName;
        Write-Host "Running init scripts synchronously. $($scripts.Count) found."
        Import-Module Sbs;
        foreach ($script in $scripts) {
            Write-Host "START init script: $($script.Name)";
            & $script.FullName;
            Write-Host "END init script: $($script.Name)";
        }
    }
}
else {
    SbsWriteHost "Init directory does not exist: $initScriptDirectory"
}

# Signal that we are ready. Write a ready file to c: so that K8S can check it.
New-Item -Path 'C:\\ready' -ItemType 'File' -Force;

# To ensure that shutdown runs only once, place a unique flag
New-Item -ItemType Directory -Path "C:\shutdownflags\" -Force;
$shutdownFlagFile = "C:\shutdownflags\" + [Guid]::NewGuid().ToString() + ".lock";
Set-Content -Path ($shutdownFlagFile) -Value "" -Force

$initStopwatch.Stop();
SbsWriteHost "Initialization completed in $($initStopwatch.Elapsed.TotalSeconds)s";

$lastCheck = (Get-Date).AddSeconds(-1);

$stopwatchEnvRefresh = [System.Diagnostics.Stopwatch]::StartNew();
$stopwatchLogForward = [System.Diagnostics.Stopwatch]::StartNew();

# It is only from this point on that we block shutdown.
try {
    [ConsoleCtrlHandler]::SetShutdownAllowed($false);

    $logConfigurations = $null;

    $validProviders = Get-WinEvent -ErrorAction SilentlyContinue -ListProvider * | 
        Where-Object { -not ($_.Name -match "^Microsoft|^Group Policy|^GroupPolicy|^System|^Windows|^ServiceModel|^SME|^SMS|^LSI|^LSA|^VDS |^amd|^iaStor") -and ($_.LogLinks.Count -eq 1) } |
        Select-Object -ExpandProperty Name |
        Where-Object { $_ -ne $null };

    while (-not [ConsoleCtrlHandler]::GetShutdownRequested()) {

        # Refresh environment every 10 seconds
        if ($stopwatchEnvRefresh.Elapsed.TotalSeconds -gt 8) {
            $changed = SbsPrepareEnv;
            if ($true -eq $changed) {
                SbsWriteHost "Environment refreshed.";
                $logConfigurations = $null;
            }
            $stopwatchEnvRefresh.Restart();
        }
        
        if (($null -eq $logConfigurations) -and (-not [String]::isNullOrWhiteSpace($Env:SBS_MONITORLOGCONFIGURATIONS))) {
            try {
                $logConfigurations = $Env:SBS_MONITORLOGCONFIGURATIONS | ConvertFrom-Json;
                Write-Host "Parsed logging configuration correctly: '$Env:SBS_MONITORLOGCONFIGURATIONS'";
                Write-Host "Wildcard providers: $($validProviders -join ', ')";
            }
            catch {
                Write-Host "Error when parsing SBS_MONITORLOGCONFIGURATIONS: $_";
                $logConfigurations = @();
                $logConfigurations += @{
                    LogName      = @('Application')
                    ProviderName = "SbsContainer"
                    Level        = @(1, 2, 3, 4, 5)
                };
            }
        }
        
        # The windows event log is everything but efficient or fast.
        if ($null -ne $logConfigurations -and $stopwatchLogForward.Elapsed.TotalSeconds -gt 6) {
            SbsFilteredEventLog -After $lastCheck -Configurations $logConfigurations -ValidProviders $validProviders;
            $stopwatchLogForward.Restart();
        }
        
        $lastCheck = Get-Date 
        Start-Sleep -Seconds 2;
    }

    # Debugging to figure out exactly what signals and in what order we are receiving
    # Confirmed that multiple CTR+C in docker compose up will only trigger CTRL_SHUTDOWN_EVENT once.
    #while($true) {
    #SbsWriteHost "---------";
    #$signals = [ConsoleCtrlHandler]::GetSignals()
    #foreach ($key in $signals.Keys) {
    #    $value = $signals[$key]
    #    $formattedDate = $value.ToString("yyyy-MM-dd HH:mm:ss") # Customize the date format as needed
    #    SbsWriteHost "$key : $formattedDate"
    #}
    #Start-Sleep -Seconds 1 # Add a small delay to make the output more readable
    #}

    # There are two ways to avoid calling shutodwn here:
    # 1. Shutdown was called somewhere else (i.e. lifecycle hook in K8S)
    # 2. SBS_AUTOSHUTDOWN was explicitly set to som
    if (($Env:SBS_DISABLEAUTOSHUTDOWN -eq "True") -or ((Test-Path $shutdownFlagFile) -eq $false)) {
        SbsWriteHost "Integrated shutdown skipped.";
    }
    else {
        & c:\entrypoint\shutdown.ps1;
    }
}
finally {
    # Allow the shutdown to proceed
    SbsWriteHost "Shutdown allowed set to true.";
    [ConsoleCtrlHandler]::SetShutdownAllowed($true);
}

#####################################
# Delete Readyness Probe
#####################################

if (Test-Path("c:\ready")) {
    Remove-Item -Path 'C:\ready' -Force;
}

##########################################
# Close processes. This piece here is SUPER important. Because we have
# increased the timeout for container runtime spun up processes
# if you have side consoles opened through docker, or what is worse
# you opened a remote console with K8S and left it open, will
# consume all this timeout.....
##########################################
$SBS_SHUTDOWNCLOSEPROCESSES = $Env:SBS_SHUTDOWNCLOSEPROCESSES;

if ($null -eq $SBS_SHUTDOWNCLOSEPROCESSES) {
    # Default to common shells
    $SBS_SHUTDOWNCLOSEPROCESSES = 'cmd,powershell,pwsh';
}

SbsWriteHost "Closing processes: $SBS_SHUTDOWNCLOSEPROCESSES";
$processNames = $SBS_SHUTDOWNCLOSEPROCESSES -split ',' | ForEach-Object { $_.Trim() }
$processes = Get-Process | Where-Object {
    $processName = $_.ProcessName;
    $processNames -icontains $processName;
};

$processes | ForEach-Object { SbsWriteHost "Will close: $($_.ProcessName) (ID: $($_.Id))" };
$processes | ForEach-Object { $_.Kill() }
