# Restore a certificate from a ZIP file
function SbsMssqlImportCert {

    param(
        [Parameter(Mandatory = $true)]
        [string]$zipPath
    )

    function Get-FileByExtension {
        param(
            [string]$folder,
            [string]$extension
        )

        Get-ChildItem -Path $folder -Filter "*.$extension" | Select-Object -First 1;
    }

    # Extract ZIP file
    $baseTempPath = [System.IO.Path]::GetTempPath();
    $uniqueTempDirPath = Join-Path -Path $baseTempPath -ChildPath (New-Guid);
    $tempDir = New-Item -ItemType Directory -Force -Path $uniqueTempDirPath;

    7z x -y "$($zipPath)" "-o$tempDir";

    # Identify files based on extensions
    $certFile = (Get-FileByExtension -folder $tempDir -extension 'cer').FullName;
    $keyFile = (Get-FileByExtension -folder $tempDir -extension 'pvk').FullName;
    $pwdPath = (Get-FileByExtension -folder $tempDir -extension 'txt').FullName;

    # This key is to support a legacy export format
    $key = Get-FileByExtension -folder $extractFolder -extension 'key';

    if ($null -ne $key) {
        $pwdKeyPath = (Get-FileByExtension -folder $tempDir -extension 'key').FullName;
        $privateKeyPassword = Get-Content $pwdPath | ConvertTo-SecureString -Key (Get-Content $pwdKeyPath);
    } else {
        $privateKeyPassword = Get-Content $pwdPath;
        $privateKeyPassword = ConvertTo-SecureString -String $privateKeyPassword -AsPlainText -Force;
    }

    icacls $certFile /grant "NT Service\MSSQLSERVER:F";
    icacls $keyFile /grant "NT Service\MSSQLSERVER:F";

    $instance = Connect-DbaInstance "localhost";
    Restore-DbaDbCertificate -SqlInstance $instance -Path $certFile -KeyFilePath $keyFile -DecryptionPassword $privateKeyPassword -Confirm:$false;

    # Cleanup
    Remove-Item -Path $tempDir -Recurse -Force;
}