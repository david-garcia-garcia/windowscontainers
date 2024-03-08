function SbsBackupDatabaseCertificate {
	param (
		[Parameter(Mandatory = $true)]
		[string]$instance,
		[Parameter(Mandatory = $true)]
		[string]$certificate,
		[Parameter(Mandatory = $true)]
		[string]$certificateDirectory
	)

	$certificateObj = Get-DbaDbCertificate -SqlInstance $instance -Certificate $certificate

	if ($certificateObj -eq $null) {
		Write-Host "No se ha encontrado el certificado $certificate en la instancia SQL."
		return
	}

	Write-Host "Respaldando certificado: $certificate"
	$dte = Get-Date
	$certBackupLocation = "${certificateDirectory}\${certificate}\"

	Add-Type -AssemblyName 'System.Web'
	$password = [System.Web.Security.Membership]::GeneratePassword(10, 2)

	$Key = New-Object Byte[] 32
	[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Key)
	$Key | Out-File "${certBackupLocation}\${certificate}_pwd.key"
	$securePass = ConvertTo-SecureString $password -AsPlainText -Force
	$securePass | ConvertFrom-SecureString -Key $Key | Out-File "${certBackupLocation}\${certificate}_pwd.txt"
	Backup-DbaDbCertificate -SqlInstance $instance -Certificate $certificate -Path $certBackupLocation -EncryptionPassword $securePass -Suffix "${Get-Date}"

	# Compress files in $certBackupLocation into a ZIP archive
	$zipFile = "${certificateDirectory}\${certificate}.zip"
	Compress-Archive -Path "${certBackupLocation}\*" -DestinationPath $zipFile

	# Remove original folder after compressing its content
	Remove-Item -Path $certBackupLocation -Recurse -Force
}