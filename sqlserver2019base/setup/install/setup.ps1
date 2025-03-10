$global:ErrorActionPreference = 'Stop'

Import-Module Sbs;

$mssqlIsoUrl = $Env:MSSQL2019INSTALL_ISO_URL;
$mssqlCuUrl = $Env:MSSQL2019INSTALL_CU_URL;
# (C) URL to the CU manual patch (https://github.com/microsoft/mssql-docker/issues/540)
$mssqlCuFixUrl = $Env:MSSQL2019INSTALL_CUFIX_URL;

# Download and extract the CU fix
$cuFixPath = "c:\setup\assembly_CU12.7z";
SbsDownloadFile -Url $mssqlCuFixUrl -Path $cuFixPath;
7z x -y -o"C:\" "$cuFixPath"
Remove-Item -Path $cuFixPath -Force;

# Download CU
New-Item -Path "C:\MSSQLUPDATES" -ItemType Directory;
SbsDownloadFile -Url $mssqlCuUrl  -Path "C:\MSSQLUPDATES\SQLServer2019-CU.exe";

# Download SQL Server ISO and extract
SbsDownloadFile -Url $mssqlIsoUrl -Path "C:\SQLServer2019-x64-ENU-Dev.iso";
New-Item -Path C:\SQLServerISO -ItemType Directory;
7z x C:\SQLServer2019-x64-ENU-Dev.iso -oC:\SQLServerISO;
Remove-Item -Path C:\SQLServer2019-x64-ENU-Dev.iso -Force;

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
. "C:\SQLServerISO\setup.exe" "/Q" "/ACTION=install" "/SUPPRESSPRIVACYSTATEMENTNOTICE" "/INSTANCEID=MSSQLSERVER" "/INSTANCENAME=MSSQLSERVER" "/FEATURES=SqlEngine,FullText" "/INSTALLSQLDATADIR=`"$installDir`"" "/SQLUSERDBDIR=`"$userDbDir`"" "/SQLUSERDBLOGDIR=`"$userDbLogDir`"" "/SQLTEMPDBDIR=`"$systemDbDir`"" "/SQLTEMPDBLOGDIR=`"$systemDbLogDir`"" "/SQLBACKUPDIR=`"$backupDir`"" "/UpdateEnabled=1" "/UseMicrosoftUpdate=0" "/TCPENABLED=1" "/NPENABLED=0" "/IACCEPTSQLSERVERLICENSETERMS" "/UPDATESOURCE=`"C:\MSSQLUPDATES`"" "/SQLSYSADMINACCOUNTS=ContainerAdministrator"

# Cleanup: Remove the ISO and extracted files

Remove-Item -Path C:\SQLServerISO -Recurse -Force;
Remove-Item -Path C:\MSSQLUPDATES -Recurse -Force;

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;