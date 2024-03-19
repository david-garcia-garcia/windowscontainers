# This powershell rebuilds and pushes all the images
# Because these cannot be hosted in a public repository
# due to MSSQL EULA you will have to use your own repo

param (
    [bool]$Push = $false,
    [bool]$Test = $false
)

function WaitForLog {
    param (
        [string]$containerName,
        [string]$logContains,
        [int]$timeoutSeconds = 10
    )

    $timeout = New-TimeSpan -Seconds $timeoutSeconds
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($sw.Elapsed -lt $timeout) {
        Start-Sleep -Seconds 1
        $logs = docker logs $containerName 2>&1
        if ($logs -match $logContains) {
            return;
        }
    }

    if ($sw.Elapsed -ge $timeout) {
        Write-Error "Timeout reached without detecting '$($logContains)' in logs. $($logs)"
    }
}

$global:ErrorActionPreference = 'Stop';

function ThrowIfError() {
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error.";
    }
}

# TODO: Write some tests with PESTER
if ($test) {

    Import-Module Pester -PassThru;

    # Check if the 'container_default' network exists
    $networkName = "container_default"
    $existingNetwork = docker network ls --format "{{.Name}}" | Where-Object { $_ -eq $networkName }

    if (-not $existingNetwork) {
        Write-Host "Network '$networkName' does not exist. Creating..."
        docker network create $networkName --driver nat --subnet=172.18.8.0/24;
        Write-Host "Network '$networkName' created."
    }
    else {
        Write-Host "Network '$networkName' already exists."
    }
}


# Core Server
Write-Host "Building $($Env:IMG_SERVERCORE2022)"
docker compose -f servercore2022/compose.yaml build
ThrowIfError

if ($test) {
    #Invoke-Pester -Output Detailed servercore2022\ComposeBasic.Tests.ps1
    #Invoke-Pester -Output Detailed servercore2022\Compose.Tests.ps1
}

if ($push) {
    docker push "$($Env:IMG_SERVERCORE2022)"
    ThrowIfError
}

# IIS Base
Write-Host "Building $($Env:IMG_SERVERCORE2022IIS)"
docker compose -f servercore2022iis/compose.yaml build
ThrowIfError

if ($test) {
    Invoke-Pester -Output Detailed servercore2022iis\Compose.Tests.ps1
    Invoke-Pester -Output Detailed servercore2022iis\ComposeCerts.Tests.ps1
}

if ($push) { 
    docker push "$($Env:IMG_SERVERCORE2022IIS)" 
    ThrowIfError
}

return;

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