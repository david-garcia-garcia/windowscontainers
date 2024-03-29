# USE THIS TO SET THE IMAGE NAMES FOR THE BUILD

param (
    [string]$containerRegistry
)

if (-not $containerRegistry -or -not $containerRegistry.EndsWith("/")) {
    Write-Error "The containerRegistry parameter is either empty or does not end with a slash."
    exit
}

$version = "1.0.21";

# To install MSSQL we need the ISO file, the latest CU
$Env:MSSQLINSTALL_ISO = "https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-x64-ENU-Dev.iso";
$Env:MSSQLINSTALL_CU = "https://download.microsoft.com/download/9/6/8/96819b0c-c8fb-4b44-91b5-c97015bbda9f/SQLServer2022-KB5033663-x64.exe";
# And a manual built patch :(, see https://github.com/microsoft/mssql-docker/issues/540
$Env:MSSQLINSTALL_CUPATCH = "https://yourblob.blob.core.windows.net/instaladorsql/assembly_CU12.7z";

$Env:IMG_SERVERCORE2022 = "$($containerregistry)servercore2022:$($version)";
$Env:IMG_SERVERCORE2022IIS = "$($containerregistry)servercore2022iis:$($version)";
$Env:IMG_SERVERCORE2022IISNET48 = "$($containerregistry)servercore2022iisnet48:$($version)";
$Env:IMG_SQLSERVER2022AS = "$($containerregistry)sqlserver2022as:$($version)";
$Env:IMG_SQLSERVER2022BASE = "$($containerregistry)sqlserver2022base:$($version)";
$Env:IMG_SQLSERVER2022K8S = "$($containerregistry)sqlserver2022k8s:$($version)";
