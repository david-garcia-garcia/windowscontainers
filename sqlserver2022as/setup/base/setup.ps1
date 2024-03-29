$global:ErrorActionPreference = 'Stop'

Import-Module Sbs;

# Install missing binaries that make the CU12 install work
# https://github.com/microsoft/mssql-docker/issues/540
$cuFixPath = "c:\setup\assembly_CU12.7z";
New-Item -Path "c:\setup" -ItemType Directory -Force;
if (-not (Test-Path $cuFixPath)) {
    # Just in case
    # $cuFixUrl = "https://yourblob.blob.core.windows.net/instaladorsql/assembly_CU12.7z";
    SbsDownloadFile -Url $cuFixUrl -Path $cuFixPath;
}

7z x -y -o"C:\" "$cuFixPath"

# Download SQL Server ISO
$installUrl = "https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-x64-ENU-Dev.iso";
SbsDownloadFile -Url $installUrl -Path "C:\SQLServer2022-x64-ENU-Dev.iso";

# Install CU
New-Item -Path C:\MSSQLUPDATES -ItemType Directory;
$cuUrl = "https://download.microsoft.com/download/9/6/8/96819b0c-c8fb-4b44-91b5-c97015bbda9f/SQLServer2022-KB5033663-x64.exe";
SbsDownloadFile -Url $cuUrl -Path "C:\MSSQLUPDATES\SQLServer2022-CU.exe";

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
"/UpdateEnabled=1",
"/UseMicrosoftUpdate=0",
"/UPDATESOURCE=`"C:\MSSQLUPDATES`"",
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
