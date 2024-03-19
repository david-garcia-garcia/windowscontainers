$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

Import-Module Sbs;

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew();

#####################################
# Setting timezone hardcoded here
#####################################

$timezone = [Environment]::GetEnvironmentVariable("SBS_CONTAINERTIMEZONE")

# Check if the timezone value was retrieved
if (-not [string]::IsNullOrWhiteSpace($timezone)) {
    # Set the timezone
    Set-TimeZone -Id $timezone;
    SbsWriteHost "Timezone set to $timezone from SBS_CONTAINERTIMEZONE";
} else {
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
# Protect environment variables using DPAPI
##########################################################################
$processEnvironmentVariables = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Process);
SbsWriteHost "Initiating ENV protection";
foreach ($key in $processEnvironmentVariables.Keys) {
    $variableName = $key.ToString()
    if ($variableName -match "^(.*)_PROTECT$") {
        Add-Type -AssemblyName System.Security;
        $originalVariableName = $matches[1];
        $originalValue = $processEnvironmentVariables[$key];
        $protectedValue = [System.Convert]::ToBase64String([System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes($originalValue), $null, 'LocalMachine'));
        [System.Environment]::SetEnvironmentVariable($originalVariableName, $protectedValue, [System.EnvironmentVariableTarget]::Process);
        Remove-Item -Path "Env:\$variableName";
        SbsWriteHost "Protected environment variable '$variableName' with DPAPI at the machine level and renamed to '$originalVariableName'";
    }
}

##########################################################################
# Promote process level env variables to machine level. This is the most straighforward
# way making these accessible ot other processes in the container such as IIS pools,
# scheduled tasks, etc.
# Some of these contain sensible information that should not be promoted or readily available
# to those services (i.e. there could be 3d party software such as NR running that will
# have access to theses inmmediately)
##########################################################################
$SBS_PROMOTE_ENV_REGEX = [System.Environment]::GetEnvironmentVariable("SBS_PROMOTE_ENV_REGEX");
if (-not [string]::IsNullOrWhiteSpace($SBS_PROMOTE_ENV_REGEX)) {
    SbsWriteHost "Initiating ENV system promotion for variables that match '$SBS_PROMOTE_ENV_REGEX'";
    $processEnvironmentVariables = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Process);
    foreach ($key in $processEnvironmentVariables.Keys) {
        $variableName = $key.ToString();
        if ($variableName -match $SBS_PROMOTE_ENV_REGEX) {
            $variableValue = [System.Environment]::GetEnvironmentVariable($variableName, [System.EnvironmentVariableTarget]::Process);
            [System.Environment]::SetEnvironmentVariable($variableName, $variableValue, [System.EnvironmentVariableTarget]::Machine);
            SbsWriteHost "Promoted environment variable: $variableName";
        }
    }
}

function Wait-JobOrThrow {
    param (
        [Parameter(Mandatory = $true)]
        [int]$JobId,
        [Parameter(Mandatory = $true)]
        [int]$Timeout
    )

    $job = Get-Job -Id $JobId;

    if (-not $job) {
        throw "Job with ID $JobId not found";
    }

    $jobName = $job.Name;

    $startTime = Get-Date;
    Wait-Job -Job $job -Timeout $Timeout;
    $endTime = Get-Date;

    $elapsed = $endTime - $startTime;
    $formattedElapsed = "{0:hh\:mm\:ss}" -f [timespan]::FromSeconds($elapsed.TotalSeconds);

    if ($job.State -eq "Running") {
        SbsWriteHost "[$(Get-Date -format 'HH:mm:ss')] Task $jobName completed with error in $formattedElapsed";
        $host.SetShouldExit(1);
        throw "Task $jobName did not complete within the specified timeout of $Timeout seconds!";
    }

    $endState = $job.State;
    Receive-Job -Job $job -Wait -AutoRemoveJob;

    # Check if the state is 'Failed' or if there are error records in the results
    if ($job.State -eq 'Failed') {
        SbsWriteHost "[$(Get-Date -format 'HH:mm:ss')] Task $jobName encountered an error during execution in $formattedElapsed";
        # Throw the first error or adjust as needed
        $host.SetShouldExit(1);
        throw "Task $jobName failed";
    }

    SbsWriteHost "[$(Get-Date -format 'HH:mm:ss')] Task $jobName completed in state $endState with success in $formattedElapsed";
}

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
$SBS_ENTRYPOINTRYNASYNC = [System.Environment]::GetEnvironmentVariable("SBS_ENTRYPOINTRYNASYNC");
$initScriptDirectory = "C:\entrypoint\init";
if (Test-Path -Path $initScriptDirectory) {
    # Get all .ps1 files in the directory
    $scripts = Get-ChildItem -Path $initScriptDirectory -Filter *.ps1 | Sort-Object Name;

    # Iterate through each script and execute it
    foreach ($script in $scripts) {
        if ($SBS_ENTRYPOINTRYNASYNC -eq 'True') {
            # Ejecutamos estos scripts así para evitar que cualquier cosa que carguen en la sesión
            # de Powershell quede bloqueada (p.e. un módulo de PS que se utilice en estos arraques
            # quedaría eternamente bloqueado en el contenedor porque el entypoint lo bloquea).
            # En princpio esto no es malo, pero si para depurar o diagnosticar hay que actualizar
            # un módulo PS que está bloqueado, no podremos sin matar el contenedor.
            SbsWriteHost "Executing init script asynchronously START: $($script.FullName)";
            # Start the script as a job
            $job = Start-Job -FilePath $script.FullName -Name $script.Name;
            Wait-JobOrThrow -JobId $job.Id -Timeout (SbsGetEnvInt 'SBS_ENTRYPOINTRYNASYNCTIMEOUT' 180);
            SbsWriteHost "Executing init script asynchronously END: $($script.FullName)";
        }
        else {
            SbsWriteHost "Executing init script synchronously START: $($script.FullName)";
            try {
                & $script.FullName;
            }
            catch {
                if ($global:ErrorActionPreference -match 'Continue') {
                    SbsWriteHost "An error was found";
                    SbsWriteHost $_;
                }
                else {
                    throw $_;
                }
            }
            SbsWriteHost "Executing init script synchronously END: $($script.FullName)";
        }
    }
}
else {
    SbsWriteHost "Init directory does not exist: $initScriptDirectory"
}

# Signal that we are ready. Write a ready file to c: so that K8S can check it.
New-Item -Path 'C:\\ready' -ItemType 'File' -Force;

$stopwatch.Stop();
SbsWriteHost "Initialization completed in $($stopwatch.Elapsed.TotalSeconds)s";

$lastCheck = (Get-Date).AddSeconds(-1);

# It is only from this point on that we block shutdown.
try {
    [ConsoleCtrlHandler]::SetShutdownAllowed($false);

    while (-not [ConsoleCtrlHandler]::GetShutdownRequested()) {
        SbsFilteredEventLog -After $lastCheck -LogNames $Env:SBS_MONITORLOGNAMES -Source $Env:SBS_MONITORLOGSOURCE -MinLevel $Env:SBS_MONITORLOGMINLEVEL;
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

    if ($Env:SBS_AUTOSHUTDOWN -ne '0') {
        SbsWriteHost "Shutdown start";
        & c:\entrypoint\shutdown.ps1;
        SbsWriteHost "Shutdown end";
    }
    else {
        SbsWriteHost "Integrated shutdown skipped.";
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

#####################################
# Close processes II
#
# Keeping this for the records, when using 
# log monitor as an entrypoint if you
# keep a shell from docker open, there seems
# to be no way to kill it from here. You need
# to manually exit it for the container to be released.
#####################################

#public class WinApi {
#    [DllImport("kernel32.dll", SetLastError = true)]
#    public static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, int processId);
#
#   [DllImport("kernel32.dll", SetLastError = true)]
#    [return: MarshalAs(UnmanagedType.Bool)]
#    public static extern bool TerminateProcess(IntPtr hProcess, uint uExitCode);
#
#    [DllImport("kernel32.dll", SetLastError = true)]
#    [return: MarshalAs(UnmanagedType.Bool)]
#    public static extern bool CloseHandle(IntPtr hObject);
#}
#'@
#
#$processes | ForEach-Object { 
#    Write-Output "Will close: $($_.ProcessName) (ID: $($_.Id))"
#    $processId = $_.Id;
#    $PROCESS_ALL_ACCESS = 0x001F0FFF;
#    $processHandle = [WinApi]::OpenProcess($PROCESS_ALL_ACCESS, $false, $processId);
#    if ($processHandle -ne [IntPtr]::Zero) {
#        [WinApi]::TerminateProcess($processHandle, 1) | Out-Null;
#        [WinApi]::CloseHandle($processHandle) | Out-Null;
#        Write-Output "Process terminated.";
#    }
#    else {
#        Write-Error "Failed to open process.";
#    }
#}