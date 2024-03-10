function SbsRestoreCertificateFromZip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$sqlInstance,
        [Parameter(Mandatory = $true)]
        [string]$zipPath
    )

    function Get-FileByExtension {
        param(
            [string]$folder,
            [string]$extension
        )

        Get-ChildItem -Path $folder -Filter "*.$extension" | Select-Object -First 1
    }

    # Check if zipPath is a URL and download the file if it is
    if ($zipPath -match '^http') {
        $urlWithoutQuery = $zipPath -replace '\?.*$';
        $fileName = [System.IO.Path]::GetFileName($urlWithoutQuery);
        $downloadedZipPath = Join-Path -Path $env:TEMP -ChildPath $fileName;
        Invoke-WebRequest -Uri $zipPath -OutFile $downloadedZipPath;
        SbsWriteHost "Downloaded certificate zip file to $downloadedZipPath";
        $zipPath = $downloadedZipPath;
    }

    # Extract ZIP file
    $zipFileName = [System.IO.Path]::GetFileNameWithoutExtension($zipPath);
    $baseTempPath = "C:\Users\Public";
    $extractFolder = Join-Path -Path $baseTempPath -ChildPath ("temp_extract_" + [Guid]::NewGuid().ToString());
    if (Test-Path $extractFolder) {
        Remove-Item -Path $extractFolder -Recurse -Force
    }
    Expand-Archive -Path $zipPath -DestinationPath $extractFolder;

    # Identify files based on extensions and validate their existence
    $certFile = (Get-FileByExtension -folder $extractFolder -extension 'cer').FullName
    if (-not (Test-Path -Path $certFile)) {
        throw "Certificate file (*.cer) not found in $extractFolder"
    }

    $keyFile = (Get-FileByExtension -folder $extractFolder -extension 'pvk').FullName
    if (-not (Test-Path -Path $keyFile)) {
        throw "Key file (*.pvk) not found in $extractFolder"
    }

    $pwdPath = (Get-FileByExtension -folder $extractFolder -extension 'txt').FullName
    if (-not (Test-Path -Path $pwdPath)) {
        throw "Password file (*.txt) not found in $extractFolder"
    }

    $pwdKeyPath = (Get-FileByExtension -folder $extractFolder -extension 'key').FullName
    if (-not (Test-Path -Path $pwdKeyPath)) {
        throw "Key password file (*.key) not found in $extractFolder"
    }

    $plainPwd = Get-Content $pwdPath | ConvertTo-SecureString -Key (Get-Content $pwdKeyPath);

    SbsWriteHost "plainPwd: $plainPwd";
    SbsWriteHost "sqlInstance: $sqlInstance";
    SbsWriteHost "certFile: $certFile";
    SbsWriteHost "keyFile: $keyFile";
    SbsWriteHost "zipFileName: $zipFileName";

    Restore-DbaDbCertificate -SqlInstance $sqlInstance -Path $certFile -KeyFilePath $keyFile -DecryptionPassword $plainPwd -Name $zipFileName -Confirm:$false;

    # Cleanup
    Remove-Item -Path $extractFolder -Recurse -Force;
}