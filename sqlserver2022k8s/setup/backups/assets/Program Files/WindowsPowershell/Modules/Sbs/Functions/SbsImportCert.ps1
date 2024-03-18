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
}