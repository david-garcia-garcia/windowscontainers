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

# Download CU
New-Item -Path "C:\MSSQLUPDATES" -ItemType Directory;
SbsDownloadFile -Url $mssqlCuUrl  -Path "C:\MSSQLUPDATES\SQLServer2022-CU.exe";

# Download SQL Server ISO
SbsDownloadFile -Url $mssqlIsoUrl -Path "C:\SQLServer2022-x64-ENU-Dev.iso";

# Use 7z to extract the ISO contents
New-Item -Path C:\SQLServerISO -ItemType Directory;
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
"/UpdateEnabled=1",
"/IACCEPTSQLSERVERLICENSETERMS",
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
