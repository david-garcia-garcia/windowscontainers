$global:ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

# Instalar choco
Write-Host "`n---------------------------------------"
Write-Host " Installing choco"
Write-Host "-----------------------------------------`n"

Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

Write-Host "`n---------------------------------------"
Write-Host " Installing 7zip"
Write-Host "-----------------------------------------`n"

# 7zip for compression/decompression
choco upgrade 7zip.install -y --version=23.1 --ignore-checksums --no-progress;

Write-Host "`n---------------------------------------"
Write-Host " Installing Micro"
Write-Host "-----------------------------------------`n"

# Command line editor
choco upgrade micro -y --version=2.0.11 --ignore-checksums --no-progress;

Write-Host "`n---------------------------------------"
Write-Host " Open SSH server"
Write-Host "-----------------------------------------`n"

Add-WindowsCapability -Online -Name OpenSSH.Server
Add-Content -Path "C:\ProgramData\ssh\sshd_config" -Value "PasswordAuthentication yes";

# Open SSL
# Bad idea, open ssl is too bloated, and download sources too slow.
#choco install openssl -y --version=3.2.1 --ignore-checksums --no-progress;
#Remove-Item -Path "C:\Program Files\OpenSSL-Win64\tests" -Recurse -Force;

Write-Host "`n---------------------------------------"
Write-Host " Setup PS repositories"
Write-Host "-----------------------------------------`n"

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Verbose -Force -Scope AllUsers;

#Set-PSRepository -Name PSGallery -InstallationPolicy Trusted;
#Set-PSRepository -Name NuGet -InstallationPolicy Trusted;

Write-Host "`n---------------------------------------"
Write-Host " Install powershell-yaml"
Write-Host "-----------------------------------------`n"

Install-Module -Name powershell-yaml -Force;

Write-Host "`n---------------------------------------"
Write-Host " Creating log source: SbsContainer"
Write-Host "-----------------------------------------`n"

New-EventLog -LogName Application -Source "SbsContainer" -ErrorAction SilentlyContinue;
Write-EventLog -LogName "Application" -Source "SbsContainer" -EventID 9900 -EntryType Information -Message "Setup script executed.";

Write-Host "`n---------------------------------------"
Write-Host " Enable long path support"
Write-Host "-----------------------------------------`n"

# Habilitar long paths (cuidado porque las aplicaciones también deben soportarlo) https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation?tabs=powershell
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force

# Write-Host "`n---------------------------------------"
# Write-Host " Disable IE Enhanced Security"
# Write-Host "-----------------------------------------`n"
# Desactivamos esto porque el motor de IE ya no se usa (usamos otros navegadores en chrome)
# y hay procesoso o scripting secundario que tiran de este motor (wget, Invoke-WebRequest)
# que se ven afectados por las restricciones de IE
# Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -Type DWord
# Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -Type DWord

Write-Host "`n---------------------------------------"
Write-Host " Enabling login/logout audit in windows"
Write-Host "-----------------------------------------`n"

$LogonSubcategoryGUID = "{0CCE9226-69AE-11D9-BED3-505054503030}"
auditpol /set /subcategory:$LogonSubcategoryGUID /success:enable /failure:enable

################################################
# Deshabilitar DiagHost, DiagTrack, Vss no parece que en un contenedor tenga mucho sentido
################################################

Stop-Service DiagHost;
Set-Service DiagHost -StartupType Disabled;
Write-Host "Disabled service DiagHost"

Stop-Service DiagTrack;
Set-Service DiagTrack -StartupType Disabled;
Write-Host "Disabled service DiagTrack"

# Snapshots, sin sentido en kubernetes
Stop-Service Vss -Force;
Set-Service Vss -StartupType Disabled;
Write-Host "Disabled service Vss"

Stop-Service SWPRV -Force;
Set-Service SWPRV -StartupType Disabled;
Write-Host "Disabled service SWPRV"

# Transacciones distribuidas, a evitar.
Stop-Service MSDTC -Force;
Set-Service MSDTC -StartupType Disabled;
Write-Host "Disabled service MSDTC"

# Este servicio NO funciona en contenedores
Stop-Service LanManServer -Force;
Set-Service LanManServer -StartupType Disabled;
Write-Host "Disabled service LanManServer"

# Updates de windows sin sentido en contenedor
Stop-Service UsoSvc -Force;
Set-Service UsoSvc -StartupType Disabled;
Write-Host "Disabled service UsoSvc"

Stop-Service UsoSvc -Force;
Set-Service UsoSvc -StartupType Disabled;
Write-Host "Disabled service sshd"

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;
