Import-Module Sbs;

SbsWriteHost "Starting teardown.";
$shutdownScriptDirectory = "C:\entrypoint\shutdown";

# Remove the shutdown flags to ensure the entrypoint does not 
Get-ChildItem -Path "C:\shutdownflags\" -File | Remove-Item;

if (Test-Path -Path $shutdownScriptDirectory) {
    # Get all .ps1 files in the directory
    $scripts = Get-ChildItem -Path $shutdownScriptDirectory -Filter *.ps1 | Sort-Object Name;
    # Iterate through each script and execute it
    foreach ($script in $scripts) {
        SbsWriteHost "Executing shutdown script: $($script.FullName)";
        try {
            & $script.FullName;
        }
        catch {
            $errorMessage = "Error executing script $($script.FullName): $($_.Exception.Message)";
            SbsWriteHost $errorMessage;
        }
    }
}
else {
    SbsWriteHost "Init directory does not exist: $shutdownScriptDirectory";
}

# Al apagar un contenedor el entrypoint recibe un SIGTERM y entramos por aquí,
# es es un contenedor de IIS así que el shutdown
SbsWriteHost "Entry point SHUTDOWN END";