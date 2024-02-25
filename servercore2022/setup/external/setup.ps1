$global:ErrorActionPreference = 'Stop'

################################################
# Deshabilitar DiagHost, DiagTrack, Vss no parece que en un contenedor tenga mucho sentido
################################################
Stop-Service DiagHost;
Set-Service DiagHost -StartupType Disabled;

Stop-Service DiagTrack;
Set-Service DiagTrack -StartupType Disabled;

# Snapshots, sin sentido en kubernetes
Stop-Service Vss -Force;
Set-Service Vss -StartupType Disabled;

Stop-Service SWPRV -Force;
Set-Service SWPRV -StartupType Disabled;

# Transacciones distribuidas, a evitar.
Stop-Service MSDTC -Force;
Set-Service MSDTC -StartupType Disabled;

# Este servicio NO funciona en contenedores
Stop-Service LanManServer -Force;
Set-Service LanManServer -StartupType Disabled;

# Updates de windows sin sentido en contenedor
Stop-Service UsoSvc -Force;
Set-Service UsoSvc -StartupType Disabled;

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

# Instalar choco
$testchoco = Get-Command -Name choco.exe -ErrorAction SilentlyContinue;
if(-not($testchoco)){
  Write-Host "`n---------------------------------------"
  Write-Host " Installing choco"
  Write-Host "-----------------------------------------`n"
  Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}
else {
  choco upgrade chocolatey -y --no-progress;
}

Write-Host "`n---------------------------------------"
Write-Host " Installing basic CHOCO packages"
Write-Host "-----------------------------------------`n"

# 7zip for compression/decompression
choco upgrade 7zip.install -y --version=23.1 --ignore-checksums --no-progress;

# Command line editor
choco upgrade micro -y --version=2.0.11 --ignore-checksums --no-progress;

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
Write-Host " Creating log source: ContainerLifecycle"
Write-Host "-----------------------------------------`n"

New-EventLog -LogName Application -Source "ContainerLifecycle" -ErrorAction SilentlyContinue;
Write-EventLog -LogName "Application" -Source "ContainerLifecycle" -EventID 9900 -EntryType Information -Message "Setup script executed.";

Write-Host "`n---------------------------------------"
Write-Host " Enable long path support"
Write-Host "-----------------------------------------`n"

# Habilitar long paths (cuidado porque las aplicaciones también deben soportarlo) https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation?tabs=powershell
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force

Write-Host "`n---------------------------------------"
Write-Host " Disable IE Enhanced Security"
Write-Host "-----------------------------------------`n"

# Desactivamos esto porque el motor de IE ya no se usa (usamos otros navegadores en chrome)
# y hay procesoso o scripting secundario que tiran de este motor (wget, Invoke-WebRequest)
# que se ven afectados por las restricciones de IE
#Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -Type DWord
#Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -Type DWord

Write-Host "`n---------------------------------------"
Write-Host " Enabling login/logout audit in windows"
Write-Host "-----------------------------------------`n"

$LogonSubcategoryGUID = "{0CCE9226-69AE-11D9-BED3-505054503030}"
auditpol /set /subcategory:$LogonSubcategoryGUID /success:enable /failure:enable

################################################
# Create local admin
################################################

$password = Add-Type -AssemblyName System.Web;
$password = -join ((33..126) * 2 | Get-Random -Count 12 | % {[char]$_});
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force;
New-LocalUser -Name "localadmin" -Password $securePassword -PasswordNeverExpires;
Add-LocalGroupMember -Group "Administrators" -Member "localadmin";

Write-Host "Created localadmin user";

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;
