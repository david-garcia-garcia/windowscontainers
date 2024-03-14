$global:ErrorActionPreference = 'Stop'

# Download SQL Server ISO
SbsDownloadFile -Url "https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-x64-ENU-Dev.iso" -Path "C:\SQLServer2022-x64-ENU-Dev.iso";

# Create a directory to extract the ISO contents
New-Item -Path C:\SQLServerISO -ItemType Directory;

# Use 7z to extract the ISO contents
7z x C:\SQLServer2022-x64-ENU-Dev.iso -oC:\SQLServerISO;

# Define directory paths
$installDir = 'C:\Program Files\Microsoft SQL Server';

# Ensure all required directories exist
New-Item -Path $installDir -ItemType Directory -Force;

# Install SQL Server from the extracted files
$process = Start-Process -Wait -NoNewWindow -FilePath "C:\SQLServerISO\setup.exe" -ArgumentList "/Q",
"/ACTION=install",
"/SUPPRESSPRIVACYSTATEMENTNOTICE",
"/FEATURES=AS",
"/INSTANCEID=MSSQLSERVER",
"/INSTANCENAME=MSSQLSERVER",
"/INSTALLSQLDATADIR=`"$installDir`"",
"/UpdateEnabled=0",
"/IACCEPTSQLSERVERLICENSETERMS",
"/ASSYSADMINACCOUNTS=ContainerAdministrator" -PassThru;

# Check the exit code
if ($process.ExitCode -ne 0) {
    Write-Error "SQL Server installation failed with exit code $($process.ExitCode)."
    exit $process.ExitCode
}

# Cleanup: Remove the ISO and extracted files
Remove-Item -Path C:\SQLServer2022-x64-ENU-Dev.iso -Force;
Remove-Item -Path C:\SQLServerISO -Recurse -Force;

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;
