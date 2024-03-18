function SbsImportCert {

    param(
        # Regular expression for matchin file names containing desired certificates
        [Parameter(Mandatory = $true)]
        [string]$Name,
        # Backup location can be a path, or a SAS url.
        [string]$BackupLocation,
        # If the certificates
        [string]$CertificatePassword
    )

    # Create a temporary directory
    $tempDir = New-Item -ItemType Directory -Force -Path ".\TempCertDir"

    # Determine source type and populate temp directory
    if ($BackupLocation -like 'https://*') {
        # Azure SAS URL
        $azcopyCommand = "azcopy copy `"$BackupLocation`" `"$($tempDir.FullName)`" --recursive --include-pattern `"$Name*.7z`""
        Invoke-Expression $azcopyCommand
        if (!$?) {
            Write-Host "Failed to download files from Azure Storage."
            Remove-Item -Path $tempDir.FullName -Recurse -Force
            return
        }
    } else {
        # Local path
        if (Test-Path -Path $BackupLocation -PathType Container) {
            # It's a directory
            Copy-Item -Path "$BackupLocation\$Name*.7z" -Destination $tempDir.FullName
        } elseif (Test-Path -Path $BackupLocation) {
            # It's a file
            Copy-Item -Path $BackupLocation -Destination $tempDir.FullName
        } else {
            Write-Host "Backup location does not exist."
            Remove-Item -Path $tempDir.FullName -Recurse -Force
            return
        }
    }

    # Decompress .7z files and process certificates
    $certFiles = Get-ChildItem -Path $tempDir.FullName -Filter "*.7z"
    foreach ($file in $certFiles) {
        $decompressPath = New-Item -ItemType Directory -Force -Path "$($tempDir.FullName)\Decompressed"
        $7zArgs = "x `"$($file.FullName)`" -o`"$decompressPath`" -y"
        if (![string]::IsNullOrEmpty($CertificatePassword)) {
            $7zArgs += " -p$CertificatePassword"
        }
        & 7z $7zArgs
        if ($?) {
            # Process the extracted certificates
            $extractedCerts = Get-ChildItem -Path $decompressPath -Filter "*.cer"
            foreach ($cert in $extractedCerts) {
                # Restore certificate to SQL Server, adjust command as needed
                Write-Host "Would restore certificate from $($cert.FullName) to localhost SQL Server instance."
                # Example: Restore-DbaDatabase -SqlInstance 'localhost' -Path $cert.FullName -WithReplace
            }
        } else {
            Write-Host "Failed to extract certificates from $file"
        }
        Remove-Item -Path $decompressPath -Recurse -Force
    }

    # Clean up
    Remove-Item -Path $tempDir.FullName -Recurse -Force
}