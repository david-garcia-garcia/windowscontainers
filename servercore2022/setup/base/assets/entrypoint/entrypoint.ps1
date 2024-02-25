$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

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
Add-Type -AssemblyName System.Security;
Write-Host "Initiating ENV protection";
foreach ($key in $processEnvironmentVariables.Keys) {
    $variableName = $key.ToString()
    if ($variableName -match "^(.*)_PROTECT$") {
        $originalVariableName = $matches[1];
        $originalValue = $processEnvironmentVariables[$key];
        $protectedValue = [System.Convert]::ToBase64String([System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes($originalValue), $null, 'LocalMachine'));
        [System.Environment]::SetEnvironmentVariable($originalVariableName, $protectedValue, [System.EnvironmentVariableTarget]::Process);
        Remove-Item -Path "Env:\$variableName";
        Write-Host "Protected environment variable '$variableName' with DPAPI at the machine level and renamed to '$originalVariableName'";
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
    Write-Host "Initiating ENV system promotion for variables that match '$SBS_PROMOTE_ENV_REGEX'";
    $processEnvironmentVariables = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Process);
    foreach ($key in $processEnvironmentVariables.Keys) {
        $variableName = $key.ToString();
        if ($variableName -match $SBS_PROMOTE_ENV_REGEX) {
            $variableValue = [System.Environment]::GetEnvironmentVariable($variableName, [System.EnvironmentVariableTarget]::Process);
            [System.Environment]::SetEnvironmentVariable($variableName, $variableValue, [System.EnvironmentVariableTarget]::Machine);
            Write-Host "Promoted environment variable: $variableName";
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
        Write-Host "[$(Get-Date -format 'HH:mm:ss')] Task $jobName completed with error in $formattedElapsed";
        $host.SetShouldExit(1);
        throw "Task $jobName did not complete within the specified timeout of $Timeout seconds!";
    }

    $endState = $job.State;
    Receive-Job -Job $job -Wait -AutoRemoveJob;

    # Check if the state is 'Failed' or if there are error records in the results
    if ($job.State -eq 'Failed') {
        Write-Host "[$(Get-Date -format 'HH:mm:ss')] Task $jobName encountered an error during execution in $formattedElapsed";
        # Throw the first error or adjust as needed
        $host.SetShouldExit(1);
        throw "Task $jobName failed";
    }

    Write-Host "[$(Get-Date -format 'HH:mm:ss')] Task $jobName completed in state $endState with success in $formattedElapsed";
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
Write-Host "Start Entry Point with error action preference $global:ErrorActionPreference";
if ($global:ErrorActionPreference -ne 'Stop') {
    Write-Warning "Entry point PS Error Action Preference is not set to STOP. This will effectively allow errors to go through. Use only for debugging purposes.";
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
            Write-Host "Executing init script asynchronously START: $($script.FullName)";
            # Start the script as a job
            $job = Start-Job -FilePath $script.FullName -Name $script.Name;
            Wait-JobOrThrow -JobId $job.Id -Timeout 180;
            Write-Host "Executing init script asynchronously END: $($script.FullName)";
        }
        else {
            Write-Host "Executing init script synchronously START: $($script.FullName)";
            & $script.FullName;
            Write-Host "Executing init script synchronously END: $($script.FullName)";
        }
    }
}
else {
    Write-Host "Init directory does not exist: $initScriptDirectory"
}

# Signal that we are ready. Write a ready file to c: so that K8S can check it.
Write-Host "Initialization Ready";
New-Item -Path 'C:\\ready' -ItemType 'File' -Force;

# It is only from this point on that we block shutdown.
try {
    [ConsoleCtrlHandler]::SetShutdownAllowed($false);

    while (-not [ConsoleCtrlHandler]::GetShutdownRequested()) {
        Start-Sleep -Seconds 1;
    }

    # Debugging to figure out exactly what signals and in what order we are receiving
    # Confirmed that multiple CTR+C in docker compose up will only trigger CTRL_SHUTDOWN_EVENT once.
    #while($true) {
        #Write-Host "---------";
        #$signals = [ConsoleCtrlHandler]::GetSignals()
        #foreach ($key in $signals.Keys) {
        #    $value = $signals[$key]
        #    $formattedDate = $value.ToString("yyyy-MM-dd HH:mm:ss") # Customize the date format as needed
        #    Write-Host "$key : $formattedDate"
        #}
        #Start-Sleep -Seconds 1 # Add a small delay to make the output more readable
    #}

    if ($Env:SBS_AUTOSHUTDOWN -ne '0') {
        Write-Host "Shutdown start";
        & c:\entrypoint\shutdown.ps1;
        Write-Host "Shutdown end";
    }
    else {
        Write-Host "Integrated shutdown skipped.";
    }
}
finally {
    # Allow the shutdown to proceed
    Write-Host "Shutdown allowed set to true.";
    [ConsoleCtrlHandler]::SetShutdownAllowed($true);
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
    # Default to cmd and powershell, which are the most common shells.
    $SBS_SHUTDOWNCLOSEPROCESSES = 'cmd,powershell,pwsh';
}

# Check if the environment variable is empty
Write-Output "Closing processes: $SBS_SHUTDOWNCLOSEPROCESSES";
$processNames = $SBS_SHUTDOWNCLOSEPROCESSES -split ',' | ForEach-Object { $_.Trim() }
$processes = Get-Process | Where-Object {
    $processName = $_.ProcessName;
    $processNames -icontains $processName;
} | Where-Object {
    # Exclude the current PowerShell process
    $_.Id -ne $PID
};
$processes | ForEach-Object { Write-Output "Will close: $($_.ProcessName) (ID: $($_.Id))" };
$processes | Stop-Process -Force;

## Delete the ready probe
Remove-Item -Path 'C:\ready' -Force;
