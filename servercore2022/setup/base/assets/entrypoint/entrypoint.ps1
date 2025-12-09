$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

Import-Module Sbs;
SbsPrintSystemInfo
SbsPrepareEnv | Out-Null;

$initStopwatch = [System.Diagnostics.Stopwatch]::StartNew();

#####################################
# Setting timezone hardcoded here
#####################################

. "c:\entrypoint\refreshenv\SetTimeZone.ps1";

#####################################
# Delete Readyness Probe
#####################################

if (Test-Path("c:\ready")) {
    SbsWriteHost "Deleting readyness probe.";
    Remove-Item -Path 'C:\ready' -Force | Out-Null;
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
[ConsoleCtrlHandler]::SetConsoleCtrlHandler($handler, $true) | Out-Null;

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
    SbsWriteWarning "Entry point PS Error Action Preference is not set to STOP. This will effectively allow errors to go through. Use only for debugging purposes.";
}

##########################################################################
# Run entry point scripts
##########################################################################
$initScriptDirectory = "C:\entrypoint\init";
$initAsync = SbsGetEnvBool "SBS_INITASYNC";

# Merge contents from SBS_INITMERGEDIR if specified
# This provides an alternative to mounting a subdirectory into c:\entrypoint\init\custom
# Docker can be flaky with nested volume mounts, so this option allows mounting a directory
# elsewhere and copying its contents to the init directory at runtime
$initMergeDir = SbsGetEnvString -name "SBS_INITMERGEDIR" -defaultValue "";
if (-not [string]::IsNullOrWhiteSpace($initMergeDir)) {
    if (Test-Path $initMergeDir) {
        SbsWriteHost "Merging initialization scripts from $initMergeDir to $initScriptDirectory";
        Copy-Item -Path "$initMergeDir\*" -Destination $initScriptDirectory -Recurse -Force;
        SbsWriteHost "Initialization scripts merged successfully";
    } else {
        SbsWriteWarning "SBS_INITMERGEDIR specified but directory does not exist: $initMergeDir";
    }
}

SbsRunScriptsInDirectory -Path $initScriptDirectory -Async $initAsync;

# Signal that we are ready. Write a ready file to c: so that K8S can check it.
New-Item -Path 'C:\\ready' -ItemType 'File' -Force | Out-Null;

# To ensure that shutdown runs only once, place a unique flag
New-Item -ItemType Directory -Path "C:\shutdownflags\" -Force | Out-Null;
$shutdownFlagFile = "C:\shutdownflags\" + [Guid]::NewGuid().ToString() + ".lock";
Set-Content -Path ($shutdownFlagFile) -Value "" -Force

$initStopwatch.Stop();

SbsWriteHost "Initialization completed in $($initStopwatch.Elapsed.TotalSeconds)s";

# If a command was provided, run that instead of the service loop.
$CommandArgs = $args
if ($CommandArgs.Length -gt 0) {
    SbsWriteHost "Running command from arguments. Main loop will be skippped.";
    $cmd = $CommandArgs[0]
    $prm = $CommandArgs[1..$($CommandArgs.Length - 1)]
    & $cmd @prm
    exit 0
}

$stopwatchEnvRefresh = [System.Diagnostics.Stopwatch]::StartNew();

$refreshEnvThresholdRegular = 8;
$refreshEnvThresholdWhenError = 30;
$refreshEnvThresholdCurrent = $refreshEnvThresholdRegular;

# It is only from this point on that we block shutdown.
try {
    [ConsoleCtrlHandler]::SetShutdownAllowed($false);

    while (-not [ConsoleCtrlHandler]::GetShutdownRequested()) {

        # Warm refresh environment configuration
        if ($stopwatchEnvRefresh.Elapsed.TotalSeconds -gt $refreshEnvThresholdCurrent) {
            try {
                $changed = SbsPrepareEnv;
                if ($true -eq $changed) {
                    # Do not refresh environment state if a shutdown is in progress
                    if (Test-Path $shutdownFlagFile) {
                        SbsWriteHost "Environment refreshed.";
                        SbsRunScriptsInDirectory -Path "c:\entrypoint\refreshenv" -Async $initAsync;
                    }
                    else {
                        SbsWriteHost "Environment refreshed but shutdown is in progress. c:\entrypoint\refreshenv scripts will NOT be called. ";
                    }
                }
                $refreshEnvThresholdCurrent = $refreshEnvThresholdRegular;
            }
            catch {
                # Set a random ENVHASH so that the ENV is refresh on next loop again, we WANT to flood the
                # logs, but we don't want to stop the pods.
                $refreshEnvThresholdCurrent = $refreshEnvThresholdWhenError;
                [System.Environment]::SetEnvironmentVariable("ENVHASH", (Get-Date).ToString("o"), [System.EnvironmentVariableTarget]::Process);
                SbsWriteHost "Error running environment update $($_.Exception.Message). Will retry in $($refreshEnvThresholdCurrent)s";
            }

            $stopwatchEnvRefresh.Restart();
        }

        Start-Sleep -Milliseconds 1000;
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
    $disableAutoShutdown = SbsGetEnvBool "SBS_DISABLEAUTOSHUTDOWN";
    if (($disableAutoShutdown -eq $true) -or ((Test-Path $shutdownFlagFile) -eq $false)) {
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
