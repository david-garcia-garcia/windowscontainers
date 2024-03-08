# USE THIS TO SET THE IMAGE NAMES FOR THE BUILD

param (
    [string]$containerRegistry
)

if (-not $containerRegistry -or -not $containerRegistry.EndsWith("/")) {
    Write-Error "The containerRegistry parameter is either empty or does not end with a slash."
    exit
}

$Env:IMG_SERVERCORE2022 = "$($containerregistry)servercore2022:1.0-beta-23";
$Env:IMG_SERVERCORE2022IIS = "$($containerregistry)servercore2022iis:1.0-beta-36";
$Env:IMG_SERVERCORE2022IISNET48 = "$($containerregistry)servercore2022iisnet48:1.0-beta-23";
$Env:IMG_SQLSERVER2022AS = "$($containerregistry)sqlserver2022as:1.0-beta-24";
$Env:IMG_SQLSERVER2022BASE = "$($containerregistry)sqlserver2022base:1.0-beta-24";
$Env:IMG_SQLSERVER2022K8S = "$($containerregistry)sqlserver2022k8s:1.0-beta-23";
