# This powershell rebuilds and pushes all the images
# Because these cannot be hosted in a public repository
# due to MSSQL EULA you will have to use your own repo

param (
    [switch]$Push = $false,
    [switch]$Test = $false,
    [string]$Images = ".*"
)


# Print all environment variables that start with IMG_
Get-ChildItem env: | ForEach-Object {
    Write-Host "Variable: $($_.Name) = $('*' * $_.Value.Length)"
}

# Ensure we are in Windows containers
if (-not(Test-Path $Env:ProgramFiles\Docker\Docker\DockerCli.exe)) {
    Get-Command docker
    Write-Warning "Docker cli not found at $Env:ProgramFiles\Docker\Docker\DockerCli.exe"
}
else {
    Write-Warning "Switching to Windows Engine"
    & $Env:ProgramFiles\Docker\Docker\DockerCli.exe -SwitchWindowsEngine
}

. .\imagenames.ps1
. .\bootstraptest.ps1
. .\importfunctions.ps1

SbsPrintSystemInfo

$global:ErrorActionPreference = 'Stop';

Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
Install-Module -Name Posh-SSH -Confirm:$false

choco upgrade dbatools -y
choco upgrade azcopy10 -y

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

# Define image configurations
$ImageConfigs = @(
    @{
        Name         = "servercore2022"
        ImageEnvVar  = "IMG_SERVERCORE2022"
        ComposeFile  = "servercore2022/compose.yaml"
        Dependencies = @()
        TestPath     = "servercore2022\tests\"
    },
    @{
        Name         = "servercore2022iis"
        ImageEnvVar  = "IMG_SERVERCORE2022IIS"
        ComposeFile  = "servercore2022iis/compose.yaml"
        Dependencies = @("servercore2022")
        TestPath     = "servercore2022iis\tests"
    },
    @{
        Name         = "servercore2022iisnet48"
        ImageEnvVar  = "IMG_SERVERCORE2022IISNET48"
        ComposeFile  = "servercore2022iisnet48/compose.yaml"
        Dependencies = @("servercore2022iis", "servercore2022")
        TestPath     = $null
    },
    # SQL Server 2017
    @{
        Name         = "sqlserver2017base"
        ImageEnvVar  = "IMG_SQLSERVER2019BASE"
        ComposeFile  = "sqlserver2017base/compose.yaml"
        Dependencies = @("servercore2022")
        TestPath     = "sqlserver2017base\tests"
    },
    # SQL Server 2019
    @{
        Name         = "sqlserver2019base"
        ImageEnvVar  = "IMG_SQLSERVER2019BASE"
        ComposeFile  = "sqlserver2019base/compose.yaml"
        Dependencies = @("servercore2022")
        TestPath     = "sqlserver2019base\tests"
    },
    # SQL Server 2022
    @{
        Name         = "sqlserver2022base"
        ImageEnvVar  = "IMG_SQLSERVER2022BASE"
        ComposeFile  = "sqlserver2022base/compose.yaml"
        Dependencies = @("servercore2022")
        TestPath     = "sqlserver2022base\tests"
    },
    @{
        Name         = "sqlserver2022k8s"
        ImageEnvVar  = "IMG_SQLSERVER2022K8S"
        ComposeFile  = "sqlserver2022k8s/compose.yaml"
        Dependencies = @("sqlserver2022base", "servercore2022")
        TestPath     = "sqlserver2022k8s\tests"
    },
    @{
        Name         = "sqlserver2022as"
        ImageEnvVar  = "IMG_SQLSERVER2022AS"
        ComposeFile  = "sqlserver2022as/compose.yaml"
        Dependencies = @("sqlserver2022base", "servercore2022")
        TestPath     = $null
    },
    @{
        Name         = "sqlserver2022is"
        ImageEnvVar  = "IMG_SQLSERVER2022IS"
        ComposeFile  = "sqlserver2022is/compose.yaml"
        Dependencies = @("sqlserver2022base", "servercore2022")
        TestPath     = $null
    }
)

# Filter images based on regex pattern and collect dependencies
$selectedImages = [System.Collections.Generic.HashSet[string]]::new()
$imagesToBuild = [System.Collections.Generic.HashSet[string]]::new()

# First pass: collect directly matched images
foreach ($config in $ImageConfigs) {
    if ($config.Name -match $Images) {
        $selectedImages.Add($config.Name) | Out-Null
    }
}

# Second pass: add dependencies first, then selected images
$imagesToBuild = [System.Collections.Generic.HashSet[string]]::new()

# Add dependencies first
foreach ($imageName in $selectedImages) {
    $config = $ImageConfigs | Where-Object { $_.Name -eq $imageName }
    foreach ($dep in $config.Dependencies) {
        $imagesToBuild.Add($dep) | Out-Null
    }
}

# Then add selected images
foreach ($imageName in $selectedImages) {
    $imagesToBuild.Add($imageName) | Out-Null
}

Write-Output "Images to build: $($imagesToBuild -join ', ')"

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

# Build all required images (including dependencies)
foreach ($imageName in $imagesToBuild) {
    $config = $ImageConfigs | Where-Object { $_.Name -eq $imageName }
    $imageVar = $config.ImageEnvVar
    Write-Output "Building $(Get-Item env:$imageVar)"
    docker compose -f $config.ComposeFile build --quiet
    ThrowIfError
}

# Test and push only selected images
foreach ($imageName in $selectedImages) {
    $config = $ImageConfigs | Where-Object { $_.Name -eq $imageName }
    
    if ($test -and $config.TestPath) {
        $PesterPreference.TestResult.OutputPath = "$TESTDIR\Nunit\$($imageName).xml"
        Invoke-Pester -Path $config.TestPath
    }

    if ($push) {
        $imageVar = $config.ImageEnvVar
        docker push "$(Get-Item env:$imageVar)"
        ThrowIfError
    }
}

if ($PesterPreference.Run.Exit.Value -and 'Failed' -eq $run.Result) { 
    exit ($run.FailedCount + $run.FailedBlocksCount + $run.FailedContainersCount) 
} 