Function SbsRunScriptsInDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [bool]$Async)
 
    if (-not (Test-Path -Path $Path)) {
        SbsWriteWarning "SbsRunScriptsInDirectory Path does not exist: $Path";
        return;
    }

    SbsWriteHost "SbsRunScriptsInDirectory run scripts in directory $Path";

    if ($Async -eq $true) {
        # We run this asynchronously for multiple reasons:
        # * Any PS loaded modules directly in the entrypoint will be LOCKED. This is an issue for debugging/hot replacing.
        # * Entrypoint init scripts can load huge modules (i.e. dbatools that uses 200MB or memory). If we run them directly in the entrypoint, the memory is not released.
        # Doing this ASYNC is a little bit slower, but it pays off in some situations.
        $job = Start-Job -ScriptBlock {
            param ($iniDir)
            Import-Module Sbs;
            # Get all .ps1 files in the directory
            $scripts = Get-ChildItem -Path $iniDir -Filter *.ps1 | Sort-Object Name;
            SbsWriteHost "Running $($scripts.count) init scripts asynchronously $(ConvertTo-Json $scripts.Name -Compress)";
            $global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }
            foreach ($script in $scripts) {
                $sw = [System.Diagnostics.Stopwatch]::StartNew();
                SbsWriteHost "$($script.Name): START ";
                & $script.FullName;
                SbsWriteHost "$($script.Name): END completed in $($sw.Elapsed.TotalSeconds)s";
            }
        } -ArgumentList $Path
        
        try {
            Receive-Job -Job $job -Wait -AutoRemoveJob;
        }
        catch {
            SbsWriteWarning "Job error: $_.Message";
        }

        # Check if the state is 'Failed' or if there are error records in the results
        if ($job.State -eq 'Failed') {
            SbsWriteWarning "Found exception while running async entrypoint scripts."
            $reason = $job.ChildJobs[0].JobStateInfo.Reason;
            SbsWriteException -Exception $reason.ErrorRecord
        }

        SbsWriteHost "Async init job state $($job.State)"
    }
    else {
        $scripts = Get-ChildItem -Path $Path -Filter *.ps1 | Sort-Object Name;
        SbsWriteHost "Running $($scripts.count) init scripts synchronously $(ConvertTo-Json $scripts.Name -Compress)";
        Import-Module Sbs;
        try {
            foreach ($script in $scripts) {
                $sw = [System.Diagnostics.Stopwatch]::StartNew();
                SbsWriteHost "$($script.Name): START";
                & $script.FullName;
                SbsWriteHost "$($script.Name): END completed in $($sw.Elapsed.TotalSeconds)s";
            }
        }
        catch {
            # We use this to convert the terminating to a non terminating error,
            # so that Error-Action influences startup behaviour the way we expect it to be.
            SbsWriteException -Exception $_
        }
        SbsWriteHost "SbsRunScriptsInDirectory completed";
    }
}