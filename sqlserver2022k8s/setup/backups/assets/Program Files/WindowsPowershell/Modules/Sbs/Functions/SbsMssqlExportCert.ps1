# Exports a certificate as a 7Z file, optionally protected by a password.
function SbsExportCert {

    [OutputType([String])]
    param(
        # Name of the certificate
        [Parameter(Mandatory = $true)]
        [string]$Name,
        # If the certificates
        [string]$Password
    )

    # Create a director for the certificate files
    $baseTempPath = [System.IO.Path]::GetTempPath();
    $uniqueTempDirPath = Join-Path -Path $baseTempPath -ChildPath (New-Guid);
    $tempDir = New-Item -ItemType Directory -Force -Path $uniqueTempDirPath;
    Write-Host "Temporary directory for cert: $tempDir";

    # Export certificate and private key
    $privateKeyPassword = SbsRandomPassword 25;
    $securePass = ConvertTo-SecureString $privateKeyPassword -AsPlainText -Force;
    $securePass | ConvertFrom-SecureString -Key $Key | Out-File "${tempDir}\${certificate}_pwd.txt";
    icacls $tempDir /grant "NT Service\MSSQLSERVER:F";
    Backup-DbaDbCertificate -SqlInstance "localhost" -Certificate $Name -Path "$($tempDir)" -EncryptionPassword $securePass -Suffix "${Get-Date}";

    # Temp file
    $tempCert = Join-Path -Path $baseTempPath -ChildPath "$($Name).7z";
    Write-Host "Temp cert writen to $tempCert";

    # Delete if exists
    Remove-Item -Path $tempCert -Force;

    if ([String]::IsNullOrWhiteSpace($CertificatePassword)) {
        7z a "$($tempCert)" "$($tempDir)\*";
    }
    else {
        7z a "$($tempCert)" "$($tempDir)\*" "-p$($Password)";
    }

    Remove-Item -Path $tempDir -Recurse -Force;

    return $tempCert;
}