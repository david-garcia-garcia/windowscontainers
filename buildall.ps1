# This powershell rebuilds and pushes all the images
# Because these cannot be hosted in a public repository
# due to MSSQL EULA you will have to use your own repo

param (
    [switch]$Push = $false,
    [switch]$Test = $false,
    [string]$Images = ".*",
    [switch]$RunningCI = $false,
    [switch]$StartContainer = $false
)


# Print all environment variables that start with IMG_
Get-ChildItem env: | ForEach-Object {
    Write-Host "Variable: $($_.Name) = $('*' * $_.Value.Length)"
}

. .\imagenames.ps1
. .\bootstraptest.ps1
. .\importfunctions.ps1
. .\buildtools.ps1

# Ensure we are in Windows containers
if ($true -eq $RunningCI) {
    Switch-ToWindowsContainers
}

SbsPrintSystemInfo

$global:ErrorActionPreference = 'Stop';

# Check commit message for [composenocache] flag
$useNoCache = $false
if ($ENV:BUILD_SOURCEVERSIONMESSAGE) {
    if ($ENV:BUILD_SOURCEVERSIONMESSAGE -match '\[composenocache\]') {
        $useNoCache = $true
        Write-Host "Commit message contains [composenocache] - will use --no-cache for docker compose build"
    }
}

if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    # TODO: This should be part of the IC image
    Write-Host "Installing Posh-SSH"
    Install-Module -Name Posh-SSH -Force -Confirm:$false -Scope CurrentUser
}

Import-Module Pester -PassThru;
$PesterPreference = [PesterConfiguration]::Default
#$PesterPreference = New-PesterConfiguration
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
        Dependencies = @("servercore2022", "sqlserver2022base")
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
    Initialize-DockerNetwork -NetworkName "container_default" -Driver "nat" -Subnet "172.18.8.0/24" -Gateway "172.18.8.1"
}

# Build all required images (including dependencies)
foreach ($imageName in $imagesToBuild) {
    $config = $ImageConfigs | Where-Object { $_.Name -eq $imageName }
    $imageVar = $config.ImageEnvVar
    Write-Output "Building $((Get-Item env:$imageVar).Value)"
    Write-Output "Using compose file $($config.ComposeFile)"
    
    $buildArgs = @("-f", $config.ComposeFile, "build", "--quiet")
    if ($useNoCache) {
        $buildArgs += "--no-cache"
        Write-Output "Using --no-cache flag (from [composenocache] commit message)"
    }
    
    $maxRetries = 5
    $retryCount = 0
    $buildSuccess = $false
    
    while ($retryCount -lt $maxRetries -and -not $buildSuccess) {
        if ($retryCount -gt 0) {
            Write-Output "Retrying docker compose build (attempt $($retryCount + 1) of $maxRetries)..."
            Start-Sleep -Seconds 5
        }
        
        docker compose $buildArgs
        if ($LASTEXITCODE -eq 0) {
            $buildSuccess = $true
        } else {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Output "Build failed with exit code $LASTEXITCODE. Will retry..."
            }
        }
    }
    
    ThrowIfError
}

# Start containers in detached mode if requested
if ($StartContainer) {
    foreach ($imageName in $selectedImages) {
        $config = $ImageConfigs | Where-Object { $_.Name -eq $imageName }
        Write-Output "Starting containers for $imageName"
        Write-Output "Using compose file $($config.ComposeFile)"
        
        docker compose -f $config.ComposeFile up -d
        ThrowIfError
    }
}

# Test and push only selected images
foreach ($imageName in $selectedImages) {
    $config = $ImageConfigs | Where-Object { $_.Name -eq $imageName }
    
    if ($test -and $config.TestPath) {
        $PesterPreference.TestResult.OutputPath = "$TESTDIR\Nunit\$($imageName).xml"
        Invoke-Pester -Path $config.TestPath
    }
    
    $imageVar = $config.ImageEnvVar
    Write-Host "Image ready $((Get-Item env:$imageVar).Value)"

    if ($push) {
        Write-Host "Pushing $((Get-Item env:$imageVar).Value)"
        docker push "$((Get-Item env:$imageVar).Value)"
        ThrowIfError
    }
}

if ($PesterPreference.Run.Exit.Value -and 'Failed' -eq $run.Result) { 
    exit ($run.FailedCount + $run.FailedBlocksCount + $run.FailedContainersCount) 
} 