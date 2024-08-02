# This powershell rebuilds and pushes all the images
# Because these cannot be hosted in a public repository
# due to MSSQL EULA you will have to use your own repo

param (
    [switch]$Push = $false,
    [switch]$Test = $false,
    [string]$Images = ".*"
)

. .\imagenames.ps1
. .\bootstraptest.ps1
. .\importfunctions.ps1

# Ensure we are in Windows containers
if (-not(Test-Path $Env:ProgramFiles\Docker\Docker\DockerCli.exe)) {
    Get-Command docker
    Write-Warning "Docker cli not found at $Env:ProgramFiles\Docker\Docker\DockerCli.exe"
}
else {
    Write-Warning "Switching to Windows Engine"
    & $Env:ProgramFiles\Docker\Docker\DockerCli.exe -SwitchWindowsEngine
}

# Info about the actual IC environment
$computerInfo = Get-WmiObject Win32_ComputerSystem | Select-Object NumberOfProcessors, NumberOfLogicalProcessors, Name, Manufacturer, Model, TotalPhysicalMemory;
$cpuInfo = Get-WmiObject -Class Win32_Processor | Select-Object CurrentClockSpeed, MaxClockSpeed, Name;
$memoryGb = [math]::round(($computerInfo.TotalPhysicalMemory / 1GB), 1);
Write-Output "SystemInfo: NumberOfLogicalProcessors: $($computerInfo.NumberOfLogicalProcessors)";
Write-Output "SystemInfo: NumberOfProcessors: $($computerInfo.NumberOfProcessors)";
Write-Output "SystemInfo: System Memory: $($memoryGb)Gb";
Write-Output "SystemInfo: CPU Clock Speed: $($cpuInfo.CurrentClockSpeed) of $($cpuInfo.MaxClockSpeed) Hz";
Write-Output "SystemInfo: CPU Name: $($cpuInfo.Name)";
Write-Output "SystemInfo: Computer Name: $($computerInfo.Name)"; 
Write-Output "SystemInfo: Manufacturer: $($computerInfo.Manufacturer)";
Write-Output "SystemInfo: Model: $($computerInfo.Model)";

$global:ErrorActionPreference = 'Stop';

Import-Module Pester -PassThru;
$PesterPreference = [PesterConfiguration]::Default
$PesterPreference.Output.Verbosity = 'Detailed'
$PesterPreference.Output.StackTraceVerbosity = 'Filtered'
$PesterPreference.TestResult.Enabled = $true
$PesterPreference.TestResult.OutputFormat = "NUnitXml"
$PesterPreference.Run.Exit = $true
#$PesterPreference.Run.SkipRemainingOnFailure = "container"

$TESTDIR = $Env:TESTDIR;
if ([string]::IsNullOrWhiteSpace($TESTDIR)) {
    $TESTDIR = Get-Location;
}

Write-Output "Current temporary directory: $($env:TEMP)";
$Env:BUILD_TEMP = $Env:TEMP;

if ($Env:REGISTRY_USER -and $Env:REGISTRY_PWD) {
    Write-Output "Container registry credentials through environment provided."
    
    # Identify the registry
    $registryHost = $Env:REGISTRY_PATH;
    if ($registryHost -and $registryHost -match '^((?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,})') {
        $registryHost = $matches[1];
        Write-Output "Remote registry host: $($registryHost)";
    }

    docker login "$($registryHost)" -u="$($Env:REGISTRY_USER)" -p="$($Env:REGISTRY_PWD)"
    ThrowIfError
}

if ($test) {

    # Check if the 'container_default' network exists
    $networkName = "container_default"
    $existingNetwork = docker network ls --format "{{.Name}}" | Where-Object { $_ -eq $networkName }

    if (-not $existingNetwork) {
        Write-Output "Network '$networkName' does not exist. Creating..."
        docker network create $networkName --driver nat --subnet=172.18.8.0/24;
        Write-Output "Network '$networkName' created."
    }
    else {
        Write-Output "Network '$networkName' already exists."
    }
}


# Core Server, always build as it is a dependency to other images
Write-Output "Building $($Env:IMG_SERVERCORE2022)"
docker compose -f servercore2022/compose.yaml build --quiet
ThrowIfError

if ("servercore2022" -match $Images) {
    if ($test) {
        $PesterPreference.TestResult.OutputPath = "$TESTDIR\Nunit\servercore2022.xml";
        Invoke-Pester -Path "servercore2022\tests\"
    }

    if ($push) {
        docker push "$($Env:IMG_SERVERCORE2022)"
        ThrowIfError
    }
}

# IIS Base, always build as it is a dependency to other images
Write-Host "Building $($Env:IMG_SERVERCORE2022IIS)"
docker compose -f servercore2022iis/compose.yaml build --quiet
ThrowIfError

if ("servercore2022iis" -match $Images) {
    if ($test) {
        $PesterPreference.TestResult.OutputPath = "$TESTDIR\Nunit\servercore2022iis.xml";
        Invoke-Pester -Path "servercore2022iis\tests"
    }

    if ($push) { 
        docker push "$($Env:IMG_SERVERCORE2022IIS)" 
        ThrowIfError
    }
}

# IIS NET 48
if ("servercore2022iisnet48" -match $Images) {
    Write-Output "Building $($Env:IMG_SERVERCORE2022IISNET48)"
    docker compose -f servercore2022iisnet48/compose.yaml build --quiet
    ThrowIfError

    if ($push) { 
        docker push "$($Env:IMG_SERVERCORE2022IISNET48)" 
        ThrowIfError
    }
}

# SQL Server Base, always build as it is a dependency to other images
Write-Output "Building $($Env:IMG_SQLSERVER2022BASE)"
docker compose -f sqlserver2022base/compose.yaml build --quiet
ThrowIfError

if ("sqlserver2022base" -match $Images) {

    if ($test) {
        $PesterPreference.TestResult.OutputPath = "$TESTDIR\Nunit\sqlserver2022base.xml";
        Invoke-Pester -Path "sqlserver2022base\tests"
    }

    if ($push) { 
        docker push "$($Env:IMG_SQLSERVER2022BASE)"
        ThrowIfError
    }
}

if ("sqlserver2022k8s" -match $Images) {

    # SQL Server K8S
    Write-Output "Building $($Env:IMG_SQLSERVER2022K8S)"
    docker compose -f sqlserver2022k8s/compose.yaml build --quiet
    ThrowIfError

    if ($test) {
        $PesterPreference.TestResult.OutputPath = "$TESTDIR\Nunit\sqlserver2022k8s.xml";
        Invoke-Pester -Path "sqlserver2022k8s\tests"
    }

    if ($push) {
        docker push "$($Env:IMG_SQLSERVER2022K8S)"
        ThrowIfError
    }
}

if ("sqlserver2022as" -match $Images) {
    # SQL Server Analysis Services
    Write-Output "Building $($Env:IMG_SQLSERVER2022AS)"
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
    Write-Output "Building $($Env:IMG_SQLSERVER2022IS)"
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