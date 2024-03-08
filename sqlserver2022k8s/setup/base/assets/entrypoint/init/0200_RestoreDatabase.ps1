########################################################
# Restore or attach the database
########################################################

$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

Import-Module dbatools;

$sqlInstance = Connect-DbaInstance -SqlInstance localhost;

$restored = $false;

# Prepare path for data, log, backup, temporary and control
$dbaDefaultPath = Get-DbaDefaultPath -SqlInstance localhost;

$backupPath = $dbaDefaultPath.Backup;
$dataPath = $dbaDefaultPath.Data;
$logPath = $dbaDefaultPath.Log;
$tempDir = $Env:SBS_TEMPORARY;

if (-not (Test-Path $backupPath)) { New-Item -ItemType Directory -Path $backupPath; }
if (-not (Test-Path $dataPath)) { New-Item -ItemType Directory -Path $dataPath; }
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath; }
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir; }

Write-Host "SQL Backup Path: $backupPath";
Write-Host "SQL Data Path: $dataPath";
Write-Host "SQL Log Path: $logPath";

$controlPath = $Env:MSSQL_PATH_CONTROL;
$databaseName = $Env:MSSQL_DATABASE;

if ($null -eq $tempDir) {
    Write-Warning "No temporary directory set in ENV SBS_TEMPORARY, using default c:\windows\temp. Note that this will consume storage inside the container mount (MAX 20GB) and can become an issue with very large databases.";
    $tempDir = "c:\windows\temp";
}

if ($restored -eq $false -and $Env:MSSQL_LIFECYCLE -eq 'ATTACH') {

    Write-Host "Lifecycle attach mode starting up..."
    $structurePath = Join-Path -Path $dataPath -ChildPath "structure.json";

    if (Test-Path $structurePath) {

        $jsonContent = Get-Content $structurePath | ConvertFrom-Json;
        
        foreach ($db in $jsonContent.databases) {
            $databaseName = $db.DatabaseName;
            $dataFiles = $db.Files | ForEach-Object { $_.PhysicalName };
            Mount-DbaDatabase -SqlInstance $sqlInstance -Database $databaseName -File $dataFiles;
            Write-EventLog -LogName 'Application' -Source 'MSSQL_MANAGEMENT' -EntryType Information -EventId 1 `
                -Message "Successfully attached database '$databaseName'";
        }
        
        $restored = $true
    }
    else {
        Write-Host "Lifecycle attach mode did not find any databases to attach. Probably running a fresh installation."
    }
}

if (($false -eq $restored) -and ($Env:MSSQL_LIFECYCLE -ne 'ATTACH')) {
    $hasData = (Get-ChildItem $dataPath -File | Measure-Object).Count -gt 0 -or (Get-ChildItem $logPath -File | Measure-Object).Count -gt 0;
    if ($hasData -eq $true) {
        Write-Error "No structure.json file was found to attach database, yet there are files in the data and log directories. Please clear them.";
        return;
    }
}

# One time startup-instructions are provided in a stand-alone file that will be consumed
# and renamed. These instructions allow things such as:
# Restore from a remote backpack file
# Restore from a remote backup file
# Restore to a point in time
# Define the path to the startup file
$startupFile = Join-Path -Path $controlPath -ChildPath "startup.yaml";

# Check if the startup file exists
if (Test-Path $startupFile) {

    Write-host "Initiating startup instructions...";

    # Load the steps from the startup file
    $steps = (Get-Content $startupFile -Raw | ConvertFrom-Yaml).steps

    # Check if there are any steps defined
    if ($steps -and $steps.Count -gt 0) {
        foreach ($step in $steps) {
            switch ($step.type) {
                'restore_bacpac' {
                    if ($step.url -match "\.zip$" -or $step.url -match "\.7z$") {
                        # Handle decompression for .zip or .7z files
                        $tempPath = [System.IO.Path]::GetTempFileName();
                        Invoke-WebRequest -Uri $step.url -OutFile $tempPath -UseBasicParsing
                        if ($step.url -match "\.zip$") {
                            Expand-Archive -Path $tempPath -DestinationPath "tempDir" -Force
                        }
                        elseif ($step.url -match "\.7z$") {
                            # Assuming 7z.exe is available in the system PATH
                            Start-Process 7z.exe -ArgumentList "x `"$tempPath`" -o`"tempDir`" -p`"$($step.pwd)`" -y" -Wait;
                        }
                        $bacpacPath = Get-ChildItem "tempDir" -Filter "*.bacpac" | Select-Object -ExpandProperty FullName -First 1;
                        Restore-DbaDatabase -SqlInstance 'localhost' -Path $bacpacPath;
                        Remove-Item "tempDir" -Recurse -Force;
                        Remove-Item $tempPath -Force;
                    }
                    else {
                        # Direct restore from URL without decompression
                        Restore-DbaDatabase -SqlInstance 'localhost' -Path $step.url;
                    }
                    $restored = $true;
                }
                'restore_full' {
                    Write-host "Initiating full backup restore";
                    # Download and import the backup certificate
                    $certUrl = $step.cert;
                    $backupUrl = $step.url;
                    if ($null -ne $certUrl) {
                        $certPath = "C:\windows\temp\tempCert.zip";
                        Invoke-WebRequest -Uri $certUrl -OutFile $certPath -UseBasicParsing -TimeoutSec 60;
                        SbsRestoreCertificateFromZip 'localhost' $certPath;
                        Write-Host "Certificate restored";
                    }
                    Write-Host "Initiating restore...";
                    # Rename and download
                    $fileName = [System.IO.Path]::GetFileName($backupUrl -replace '\?.*$');
                    $localFilePath = Join-Path -Path $tempDir -ChildPath $fileName;
                    if (Test-Path $localFilePath) { Remove-Item $localFilePath }
                    c:\dbscripts\downloadFile $backupUrl $localFilePath $localFilePath;
                    # Grant permissions
                    icacls $localFilePath /grant "NT Service\MSSQLSERVER:F"
                    # Restore
                    Restore-DbaDatabase -SqlInstance 'localhost' -DatabaseName $databaseName -Path $localFilePath -WithReplace -UseDestinationDefaultDirectories -Verbose;
                    # Clean
                    Remove-Item -Path $localFilePath -Force;
                    $restored = $true;
                    [System.Diagnostics.EventLog]::WriteEntry('MSSQL_MANAGEMENT', "Restored database from $backupUrl.", [System.Diagnostics.EventLogEntryType]::Information);
                }
                default {
                    Write-Host "$($step.type) not supported.";
                }
            }
        }
    }

    SbsArchiveFile $startupFile;
}
else {
    Write-Host "Startup file not found at path $startupFile, resuming regular lifecycle startup."
}

# If nothing was restored try from a backup
if ($restored -eq $false) {
    Write-Host "Starting database restore...";
    $restoreResult = Restore-DbaDatabase -SqlInstance $sqlInstance -DatabaseName $databaseName -Path $backupPath -WithReplace -UseDestinationDefaultDirectories -Verbose;

    # Output the restored database names
    foreach ($db in $restoreResult) {
        Write-Output "Database restored: $($db.Database)";
    }
}
