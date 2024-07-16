# This powershell rebuilds and pushes all the images
# Because these cannot be hosted in a public repository
# due to MSSQL EULA you will have to use your own repo

param (
    [switch]$Push = $false,
    [switch]$Test = $false,
    [string]$Images = ".*"
)

.\imagenames.ps1

$global:ErrorActionPreference = 'Stop';

Import-Module Pester -PassThru;
$PesterPreference = [PesterConfiguration]::Default
$PesterPreference.Output.Verbosity = 'Detailed'

$TESTDIR = $Env:TESTDIR;
if ([string]::IsNullOrWhiteSpace($TESTDIR)) {
    $TESTDIR = Get-Location;
}

#$PesterPreference.TestResult.OutputFormat = "NUnitXml"
#$PesterPreference.TestResult.OutputPath = "c:\windows\Test.xml"

function ThrowIfError() {
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Last exit code was NOT 0.";
    }
}

if ($Env:REGISTRY_USER -and $Env:REGISTRY_PWD) {
    Write-Host "Container registry credentials through environment provided."
    
    # Identify the registry
    $registryHost = $Env:REGISTRY_PATH;
    if ($registryHost -and $registryHost -match '^((?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,})') {
        $registryHost = $matches[1];
        Write-Host "Remote registry host: $($registryHost)";
    }

    docker login "$($registryHost)" -u="$($Env:REGISTRY_USER)" -p="$($Env:REGISTRY_PWD)"
    ThrowIfError
}

if ($test) {

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


# Core Server, always build as it is a dependency to other images
Write-Host "Building $($Env:IMG_SERVERCORE2022)"
docker compose -f servercore2022/compose.yaml build --quiet
ThrowIfError

if ("servercore2022" -match $Images) {
    if ($test) {
        $testOutputFile = "$TESTDIR\\NUNIT\\servercore2022.xml";
        Write-Host "Test output file: $testOutputFile"
        Invoke-Pester -Path "servercore2022\tests\" -OutputFile $testOutputFil  -OutputFormat NUnitXml
    }

    if ($push) {
        docker push "$($Env:IMG_SERVERCORE2022)"
        ThrowIfError
    }
}

return;

# IIS Base, always build as it is a dependency to other images
Write-Host "Building $($Env:IMG_SERVERCORE2022IIS)"
docker compose -f servercore2022iis/compose.yaml build --quiet
ThrowIfError

if ("servercore2022iis" -match $Images) {
    if ($test) {
        Invoke-Pester -Path "servercore2022iis\tests" -OutputFile "$TESTDIR\\NUNIT\\servercore2022iis.xml" -OutputFormat NUnitXml
    }

    if ($push) { 
        docker push "$($Env:IMG_SERVERCORE2022IIS)" 
        ThrowIfError
    }
}

# IIS NET 48
if ("servercore2022iisnet48" -match $Images) {
    Write-Host "Building $($Env:IMG_SERVERCORE2022IISNET48)"
    docker compose -f servercore2022iisnet48/compose.yaml build --quiet
    ThrowIfError

    if ($push) { 
        docker push "$($Env:IMG_SERVERCORE2022IISNET48)" 
        ThrowIfError
    }
}

# SQL Server Base, always build as it is a dependency to other images
Write-Host "Building $($Env:IMG_SQLSERVER2022BASE)"
docker compose -f sqlserver2022base/compose.yaml build --quiet
ThrowIfError

if ("sqlserver2022base" -match $Images) {
    if ($push) { 
        docker push "$($Env:IMG_SQLSERVER2022BASE)"
        ThrowIfError
    }
}

if ("sqlserver2022k8s" -match $Images) {

    # SQL Server K8S
    Write-Host "Building $($Env:IMG_SQLSERVER2022K8S)"
    docker compose -f sqlserver2022k8s/compose.yaml build --quiet
    ThrowIfError

    if ($test) {
        Invoke-Pester -Path "sqlserver2022k8s\tests" -OutputFile "$TESTDIR\\NUNIT\\sqlserver2022k8s.xml" -OutputFormat NUnitXml
    }

    if ($push) {
        docker push "$($Env:IMG_SQLSERVER2022K8S)"
        ThrowIfError
    }
}

if ("sqlserver2022as" -match $Images) {
    # SQL Server Analysis Services
    Write-Host "Building $($Env:IMG_SQLSERVER2022AS)"
    docker compose -f sqlserver2022as/compose.yaml build --quiet
    ThrowIfError

    if ($test) {
    }
    if ($push) {
        docker push "$($Env:IMG_SQLSERVER2022AS)"
        ThrowIfError
    }
}

if ("sqlserver2022is" -match $Images) {
    # SQL Server Integration Services
    Write-Host "Building $($Env:IMG_SQLSERVER2022IS)"
    docker compose -f sqlserver2022is/compose.yaml build --quiet
    ThrowIfError

    if ($test) {
    }
    if ($push) {
        docker push "$($Env:IMG_SQLSERVER2022IS)"
        ThrowIfError
    }
}

if ($PesterPreference.Run.Exit.Value -and 'Failed' -eq $run.Result) { 
    exit ($run.FailedCount + $run.FailedBlocksCount + $run.FailedContainersCount) 
} 