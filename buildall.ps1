# This powershell rebuilds and pushes all the images
# Because these cannot be hosted in a public repository
# due to MSSQL EULA you will have to use your own repo

$containerregistry = "myregistry.azurecr.io/core/"
$push = $false;

$IMG_SERVERCORE2022 = "$($containerregistry)servercore2022:beta-22";
$IMG_SQLSERVER2022AS = "$($containerregistry)sqlserver2022as:beta-22";
$IMG_SQLSERVER2022BASE = "$($containerregistry)sqlserver2022base:beta-22";
$IMG_SQLSERVER2022K8S = "$($containerregistry)sqlserver2022k8s:beta-22";

# Core Server
docker build -t "$IMG_SERVERCORE2022" -f servercore2022/dockerfile servercore2022
if ($push) {
    docker push "$IMG_SERVERCORE2022"
}

# SQL Server Base
docker build --build-arg IMG_SERVERCORE2022="$IMG_SERVERCORE2022" -t "$IMG_SQLSERVER2022BASE" -f sqlserver2022base/dockerfile sqlserver2022base
if ($push) { 
    docker push "$IMG_SERVERCORE2022BASE" 
}

# SQL Server Analysis Services
docker build --build-arg IMG_SERVERCORE2022="$IMG_SERVERCORE2022" -t "$IMG_SQLSERVER2022AS" -f sqlserver2022as/dockerfile sqlserver2022as
docker push "$IMG_SERVERCORE2022AS"

# SQL Server K8S
docker build --build-arg IMG_SQLSERVER2022BASE="$IMG_SQLSERVER2022BASE" -t "$IMG_SQLSERVER2022K8S" -f sqlserver2022k8s/dockerfile sqlserver2022k8s
docker push "$IMG_SQLSERVER2022K8S"