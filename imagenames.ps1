# USE THIS TO SET THE IMAGE NAMES FOR THE BUILD

param (
    [string]$containerRegistry
)

$Env:IMG_SERVERCORE2022 = "$($containerregistry)servercore2022:beta-22";
$Env:IMG_SQLSERVER2022AS = "$($containerregistry)sqlserver2022as:beta-22";
$Env:IMG_SQLSERVER2022BASE = "$($containerregistry)sqlserver2022base:beta-22";
$Env:IMG_SQLSERVER2022K8S = "$($containerregistry)sqlserver2022k8s:beta-22";