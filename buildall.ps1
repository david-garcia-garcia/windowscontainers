# This powershell rebuilds and pushes all the images
# Because these cannot be hosted in a public repository
# due to MSSQL EULA you will have to use your own repo

param (
    [bool]$push = $false
)

$global:ErrorActionPreference = 'Stop';

function ThrowIfError() {
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error.";
    }
}

# Core Server
Write-Host "Building $($Env:IMG_SERVERCORE2022)"
docker compose -f servercore2022/compose.yaml build
ThrowIfError

if ($push) {
    docker push "$($Env:IMG_SERVERCORE2022)"
    ThrowIfError
}

# IIS Base
Write-Host "Building $($Env:IMG_SERVERCORE2022IIS)"
docker compose -f servercore2022iis/compose.yaml build
ThrowIfError

if ($push) { 
    docker push "$($Env:IMG_SERVERCORE2022IIS)" 
    ThrowIfError
}

# IIS NET 48
Write-Host "Building $($Env:IMG_SERVERCORE2022IISNET48)"
docker compose -f servercore2022iisnet48/compose.yaml build
ThrowIfError

if ($push) { 
    docker push "$($Env:IMG_SERVERCORE2022IISNET48)" 
    ThrowIfError
}

# SQL Server Base
Write-Host "Building $($Env:IMG_SQLSERVER2022BASE)"
docker compose -f sqlserver2022base/compose.yaml build
ThrowIfError

if ($push) { 
    docker push "$($Env:IMG_SQLSERVER2022BASE)"
    ThrowIfError
}

# SQL Server Analysis Services
Write-Host "Building $($Env:IMG_SQLSERVER2022AS)"
docker compose -f sqlserver2022as/compose.yaml build
ThrowIfError

if ($push) {
    docker push "$($Env:IMG_SQLSERVER2022AS)"
    ThrowIfError
}

# SQL Server K8S
Write-Host "Building $($Env:IMG_SQLSERVER2022K8S)"
docker compose -f sqlserver2022k8s/compose.yaml build
ThrowIfError

if ($push) {
    docker push "$($Env:IMG_SQLSERVER2022K8S)"
    ThrowIfError
}