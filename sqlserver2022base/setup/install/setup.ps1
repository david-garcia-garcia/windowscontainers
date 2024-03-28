$global:ErrorActionPreference = 'Stop'

Import-Module Sbs;

# Download SQL Server ISO
$installUrl = "https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-x64-ENU-Dev.iso";
SbsDownloadFile -Url $installUrl -Path "C:\SQLServer2022-x64-ENU-Dev.iso";

# Install CU
New-Item -Path C:\MSSQLUPDATES -ItemType Directory;
$cuUrl = "https://download.microsoft.com/download/9/6/8/96819b0c-c8fb-4b44-91b5-c97015bbda9f/SQLServer2022-KB5033663-x64.exe";
SbsDownloadFile -Url $cuUrl -Path "C:\MSSQLUPDATES\SQLServer2022-CU.exe";

# Use 7z to extract the ISO contents
New-Item -Path C:\SQLServerISO -ItemType Directory;
7z x C:\SQLServer2022-x64-ENU-Dev.iso -oC:\SQLServerISO;

# Define directory paths
$systemDbDir = 'C:\SQLSystemDB\Data';
$systemDbLogDir = 'C:\SQLSystemDB\Log';
$userDbDir = 'C:\SQLUserDB\Data';
$userDbLogDir = 'C:\SQLUserDB\Log';
$backupDir = 'C:\SQLBackup';
$installDir = 'C:\Program Files\Microsoft SQL Server';

# Ensure all required directories exist
New-Item -Path $systemDbDir, $systemDbLogDir, $userDbDir, $userDbLogDir, $backupDir, $installDir -ItemType Directory -Force;

# Install SQL Server from the extracted files
$process = Start-Process -Wait -NoNewWindow -FilePath "C:\SQLServerISO\setup.exe" -ArgumentList "/Q",
"/ACTION=install",
"/SUPPRESSPRIVACYSTATEMENTNOTICE",
"/INSTANCEID=MSSQLSERVER",
"/INSTANCENAME=MSSQLSERVER",
"/FEATURES=SqlEngine,FullText",
"/INSTALLSQLDATADIR=`"$installDir`"",
"/SQLUSERDBDIR=`"$userDbDir`"",
"/SQLUSERDBLOGDIR=`"$userDbLogDir`"",
"/SQLTEMPDBDIR=`"$systemDbDir`"",
"/SQLTEMPDBLOGDIR=`"$systemDbLogDir`"",
"/SQLBACKUPDIR=`"$backupDir`"",
"/UpdateEnabled=1",
"/UseMicrosoftUpdate=0",
"/TCPENABLED=1", 
"/NPENABLED=0",
"/IACCEPTSQLSERVERLICENSETERMS",
"/UPDATESOURCE=`"C:\MSSQLUPDATES`"",
"/SQLSYSADMINACCOUNTS=ContainerAdministrator" -PassThru;

# Check the exit code
if ($process.ExitCode -ne 0) {
    Write-Error "SQL Server installation failed with exit code $($process.ExitCode)."
    exit $process.ExitCode
}

# Cleanup: Remove the ISO and extracted files
Remove-Item -Path C:\SQLServer2022-x64-ENU-Dev.iso -Force;
Remove-Item -Path C:\SQLServerISO -Recurse -Force;
Remove-Item -Path C:\MSSQLUPDATES -Recurse -Force;

if ($process.ExitCode -ne 0) {
    Write-Error "SQL Server installation failed with exit code $($process.ExitCode)."
    exit $process.ExitCode
}

# Install DBA tools
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted;
choco install dbatools -y --version=2.1.11 --no-progress;

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;