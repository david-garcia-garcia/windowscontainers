
# Create or restore a backup certificate
function SbsEnsureCert {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Server,
        [Parameter(Mandatory = $true)]
        [string]$Instance,
        [Parameter(Mandatory = $true)]
        [string]$BackupLocation,
        # Optional parameter to set a password for the compressed cert backup
        [string]$CertificatePassword
    )

    $instanceName = "localhost";
    $certificate = $Name;
    $serverName = $Server;

    $certBackupLocation = "$($BackupLocation)\CERTS\${serverName}\${instanceName}\${certificate}.7z";
    Write-Host "Backup location $certBackupLocation";

    $existingCertificate = Get-DbaDbCertificate -SqlInstance $instance -Certificate $certificate;
    Write-Host "Cert '$certificate' exists $($null -ne $existingCertificate)";

    $existingCertificateBackup = Test-Path $certBackupLocation;
    Write-Host "Cert '$certificate' backup exists $existingCertificateBackup";

    # We must ensure that both the certificate and the backup exist
    if (($null -ne $existingCertificate) -or ($true -eq $existingCertificateBackup)) {
        Write-Host "Certificate or certificate backup already exist.";
        return;
    }

    SbsWriteHost "Generating certificate '$($certificate)'";	

    # Generate the certificate if it is missing
    if ($nul -eq $existingCertificate) {
        SbsWriteHost "Generating new certificate $($certificate)";
        New-DbaDbCertificate -SqlInstance $instance -ExpirationDate (Get-Date).AddYears(1) -Name $certificate;
    }

    # Prepare a temp directory
    $baseTempPath = [System.IO.Path]::GetTempPath();
    $uniqueDirName = [System.IO.Path]::GetRandomFileName();
    $uniqueTempDirPath = Join-Path -Path $baseTempPath -ChildPath $uniqueDirName;
    New-Item -ItemType Directory -Path $uniqueTempDirPath;
    icacls $uniqueTempDirPath /grant "NT Service\MSSQLSERVER:F";

    Backup-DbaDbCertificate -SqlInstance $instance -Certificate $certificate -Path $uniqueTempDirPath -EncryptionPassword $securePass -Suffix "${Get-Date}";

    # We only want to backup the single certificate file
    $certFile = (Get-ChildItem -Path $uniqueTempDirPath -File | Select-Object -First 1).FullName;

    # We ZIP in both cases, to have consistent naming for the backups, wether we use password or not.
    if ([String]::IsNullOrWhiteSpace($CertificatePassword)) {
        7z a "$($certBackupLocation)" "$($certFile)" -p$CertificatePassword;
    } else {
        7z a "$($certBackupLocation)" "$($certFile)";
    }

    SbsWriteHost "Certificate backup writen to '$($certBackupLocation)'";
    Remove-Item -Path $uniqueTempDirPath -Recurse -Force;
}