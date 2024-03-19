# USE THIS TO SET THE IMAGE NAMES FOR THE BUILD

param (
    [string]$containerRegistry
)

if (-not $containerRegistry -or -not $containerRegistry.EndsWith("/")) {
    Write-Error "The containerRegistry parameter is either empty or does not end with a slash."
    exit
}

$version = "1.1.0-beta1";

$Env:IMG_SERVERCORE2022 = "$($containerregistry)servercore2022:$($version)";
$Env:IMG_SERVERCORE2022IIS = "$($containerregistry)servercore2022iis:$($version)";
$Env:IMG_SERVERCORE2022IISNET48 = "$($containerregistry)servercore2022iisnet48:$($version)";
$Env:IMG_SQLSERVER2022AS = "$($containerregistry)sqlserver2022as:$($version)";
$Env:IMG_SQLSERVER2022BASE = "$($containerregistry)sqlserver2022base:$($version)";
$Env:IMG_SQLSERVER2022K8S = "$($containerregistry)sqlserver2022k8s:$($version)";
