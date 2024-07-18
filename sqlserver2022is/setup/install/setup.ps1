$global:ErrorActionPreference = 'Stop'

Import-Module Sbs;

$mssqlIsoUrl = $Env:MSSQLINSTALL_ISO_URL;
$mssqlCuUrl = $Env:MSSQLINSTALL_CU_URL;
# (C) URL to the CU manual patch (https://github.com/microsoft/mssql-docker/issues/540)
$mssqlCuFixUrl = $Env:MSSQLINSTALL_CUFIX_URL;

# Download and extract the CU fix
$cuFixPath = "c:\setup\assembly_CU12.7z";
SbsDownloadFile -Url $mssqlCuFixUrl -Path $cuFixPath;
7z x -y -o"C:\" "$cuFixPath"
Remove-Item -Path $cuFixPath -Force;

# Download CU
New-Item -Path "C:\MSSQLUPDATES" -ItemType Directory;
SbsDownloadFile -Url $mssqlCuUrl  -Path "C:\MSSQLUPDATES\SQLServer2022-CU.exe";

# Download SQL Server ISO and extract
SbsDownloadFile -Url $mssqlIsoUrl -Path "C:\SQLServer2022-x64-ENU-Dev.iso";
New-Item -Path C:\SQLServerISO -ItemType Directory;
7z x C:\SQLServer2022-x64-ENU-Dev.iso -oC:\SQLServerISO;
Remove-Item -Path C:\SQLServer2022-x64-ENU-Dev.iso -Force;

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
. "C:\SQLServerISO\setup.exe" "/Q" "/ACTION=install" "/SUPPRESSPRIVACYSTATEMENTNOTICE" "/INSTANCEID=MSSQLSERVER" "/INSTANCENAME=MSSQLSERVER" "/FEATURES=IS,SqlEngine" "/INSTALLSQLDATADIR=`"$installDir`"" "/SQLUSERDBDIR=`"$userDbDir`"" "/SQLUSERDBLOGDIR=`"$userDbLogDir`"" "/SQLTEMPDBDIR=`"$systemDbDir`"" "/SQLTEMPDBLOGDIR=`"$systemDbLogDir`"" "/SQLBACKUPDIR=`"$backupDir`"" "/UpdateEnabled=1" "/UseMicrosoftUpdate=0" "/TCPENABLED=1" "/NPENABLED=0" "/IACCEPTSQLSERVERLICENSETERMS" "/UPDATESOURCE=`"C:\MSSQLUPDATES`"" "/SQLSYSADMINACCOUNTS=ContainerAdministrator"

# Cleanup: Remove the ISO and extracted files

Remove-Item -Path C:\SQLServerISO -Recurse -Force;
Remove-Item -Path C:\MSSQLUPDATES -Recurse -Force;

# Install DBA tools
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted;
choco install dbatools -y --version=2.1.20 --no-progress;

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;