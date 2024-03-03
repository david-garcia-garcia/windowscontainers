# This powershell rebuilds and pushes all the images
# Because these cannot be hosted in a public repository
# due to MSSQL EULA you will have to use your own repo

param (
    [bool]$push = $false
)

# Core Server
Write-Host "Building $IMG_SERVERCORE2022"
docker compose -f servercore2022/compose.yaml build

if ($push) {
    docker push "$IMG_SERVERCORE2022"
}

# SQL Server Base
Write-Host "Building $IMG_SERVERCORE2022BASE"
docker compose -f sqlserver2022base/compose.yaml build

if ($push) { 
    docker push "$IMG_SERVERCORE2022BASE" 
}

# SQL Server Analysis Services
Write-Host "Building $IMG_SERVERCORE2022AS"
docker compose -f sqlserver2022as/compose.yaml build

if ($push) {
    docker push "$IMG_SERVERCORE2022AS"
}

# SQL Server K8S
Write-Host "Building $IMG_SQLSERVER2022K8S"
docker compose -f sqlserver2022k8s/compose.yaml build

if ($push) {
    docker push "$IMG_SQLSERVER2022K8S"
}