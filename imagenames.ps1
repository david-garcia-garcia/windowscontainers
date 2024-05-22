# USE THIS TO SET THE IMAGE NAMES FOR THE BUILD

param (
    [string]$containerRegistry
)

if (-not $containerRegistry -or -not $containerRegistry.EndsWith("/")) {
    Write-Error "The containerRegistry parameter is either empty or does not end with a slash."
    exit
}

$version = "1.0.31";

# Installation media for MSSQL
$Env:MSSQLINSTALL_ISO_URL = "https://controlstorageaccount.blob.core.windows.net/software/sqlserver2022_dev/SQLServer2022-x64-ENU-Dev.iso?sv=2023-11-03&st=2024-05-21T17%3A47%3A41Z&se=2024-05-22T17%3A47%3A41Z&sr=b&sp=r&sig=rw1RHL6LCQbyRSCHpeIvoL588E2g7yFSHkvN%2FQGk0WI%3D";
$Env:MSSQLINSTALL_CU_URL = "https://controlstorageaccount.blob.core.windows.net/software/sqlserver2022_dev/CU13/SQLServer2022-KB5036432-x64.exe?sv=2023-11-03&st=2024-05-21T17%3A48%3A15Z&se=2024-05-22T17%3A48%3A15Z&sr=b&sp=r&sig=5jXjscxK37MkD0Jxmi1ZeZ2oO%2Bo1wmyXEEddr9SfZEk%3D";
$Env:MSSQLINSTALL_CUFIX_URL = "https://controlstorageaccount.blob.core.windows.net/software/sqlserver2022_dev/CU13/assembly_CU13.7z?sv=2023-11-03&st=2024-05-21T17%3A48%3A00Z&se=2024-05-22T17%3A48%3A00Z&sr=b&sp=r&sig=9SkePE%2FbO97XTn9yjBQ%2BOtRO41txDUXJ%2FQpfMohyqW0%3D";

# Image names
$Env:IMG_SERVERCORE2022 = "$($containerregistry)servercore2022:$($version)";
$Env:IMG_SERVERCORE2022IIS = "$($containerregistry)servercore2022iis:$($version)";
$Env:IMG_SERVERCORE2022IISNET48 = "$($containerregistry)servercore2022iisnet48:$($version)";
$Env:IMG_SQLSERVER2022AS = "$($containerregistry)sqlserver2022as:$($version)";
$Env:IMG_SQLSERVER2022BASE = "$($containerregistry)sqlserver2022base:$($version)";
$Env:IMG_SQLSERVER2022K8S = "$($containerregistry)sqlserver2022k8s:$($version)";

