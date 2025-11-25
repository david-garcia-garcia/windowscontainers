function OutputLog {
    param (
        [string]$containerName
    )

    $logs = Invoke-Command -Script {
        $ErrorActionPreference = "silentlycontinue"
        docker logs $containerName --tail 250 2>&1
    } -ErrorAction SilentlyContinue
    Write-Host "---------------- LOGSTART"
    Write-Host ($logs -join "`r`n")
    Write-Host "---------------- LOGEND"
}

function WaitForLog {
    param (
        [string]$containerName,
        [string]$logContains,
        [switch]$extendedTimeout
    )

    $timeoutSeconds = 20;

    if ($extendedTimeout) {
        $timeoutSeconds = 60;
    }

    $timeout = New-TimeSpan -Seconds $timeoutSeconds
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($sw.Elapsed -le $timeout) {
        Start-Sleep -Seconds 1
        $logs = Invoke-Command -Script {
            $ErrorActionPreference = "silentlycontinue"
            docker logs $containerName --tail 350 2>&1
        } -ErrorAction SilentlyContinue
        if ($logs -match $logContains) {
            return;
        }
    }
    Write-Host "---------------- LOGSTART"
    Write-Host ($logs -join "`r`n")
    Write-Host "---------------- LOGEND"
    Write-Error "Timeout reached without detecting '$($logContains)' in logs after $($sw.Elapsed.TotalSeconds)s"
}

function ThrowIfError() {
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Last exit code was NOT 0.";
    }
}

function HoldBuild() {
    # This method should create a file, and hold in a loop with a sleep
    # until the file is deleted
    # $Env:BUILD_TEMP this is the directory where the file should be crated
    # Define the full path for the file
    $filePath = Join-Path -Path $Env:BUILD_TEMP -ChildPath "holdbuild.txt"

    # Create the file
    New-Item -ItemType File -Path $filePath -Force

    Write-Host "Created file: $filePath"

    # Hold in a loop until the file is deleted
    while (Test-Path $filePath) {
        Start-Sleep -Seconds 10
        Write-Host "Build held until file is deleted: $filePath "
    }

    Write-Host "File deleted: $filePath"
}

function Write-TimeLog {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Switch-ToWindowsContainers {
    # Ensure we are in linux containers mode
    if (-not(Test-Path $Env:ProgramFiles\Docker\Docker\DockerCli.exe)) {
        Get-Command docker
        Write-Warning "Docker cli not found at $Env:ProgramFiles\Docker\Docker\DockerCli.exe"
    }
    else {
        Write-Host "Current docker context"
        docker context ls
        ThrowIfError

        $currentContext = docker context show
        Write-Host "Current context: $currentContext";

        if ($currentContext -ne "desktop-windows") {
            Write-Warning "Switching to Windows Engine"
            & $Env:ProgramFiles\Docker\Docker\DockerCli.exe -SwitchWindowsEngine
            ThrowIfError

            $currentContext = docker context show
            Write-Host "Current context: $currentContext";

            if ($currentContext -ne "desktop-windows") {
                $contexts = docker context ls --format "{{.Name}}" 2>$null
                $desktopWindowsContextExists = $contexts -contains "desktop-windows"
                if ($desktopWindowsContextExists) {
                    Write-Warning "Desktop Windows context found, switching to desktop-windows context"
                    docker context use desktop-windows
                    ThrowIfError
                }
                else {
                    Write-Warning "Desktop Windows context not found, skipping context switch. Using context: $currentContext"
                }
            }    
            else {
                Write-Warning "Desktop Windows context not found, skipping context switch. Using context: $currentContext"
            }
        }
        else {
            Write-Information "Running on Windows Containers."
        }
    }
}

function Remove-DockerNetworkByName {
    param (
        [string]$NetworkName
    )
    
    # Forcefully remove any existing network with the same name to avoid conflicts
    $existingNetwork = docker network ls --filter "name=$NetworkName" --format "{{.ID}}"
    if ($existingNetwork) {
        Write-Host "Removing existing Docker network: $NetworkName"
        docker network rm $NetworkName
        ThrowIfError
    }
}

function Get-DockerNetworks {
    $networks = @()
    $existingNetworks = docker network ls --format "{{.Name}}" 2>$null
    if ($existingNetworks) {
        foreach ($net in $existingNetworks) {
            $subnet = docker network inspect $net --format "{{range .IPAM.Config}}{{.Subnet}}{{end}}" 2>$null
            $gateway = docker network inspect $net --format "{{range .IPAM.Config}}{{.Gateway}}{{end}}" 2>$null
            $driver = docker network inspect $net --format "{{.Driver}}" 2>$null
            
            if ($subnet -or $gateway) {
                $networks += [PSCustomObject]@{
                    Name    = $net
                    Subnet  = $subnet
                    Gateway = $gateway
                    Driver  = $driver
                }
            }
        }
    }
    return $networks
}

function Show-NetworkSetup {
    Write-TimeLog "Network details (subnets and gateways):"
    $networks = Get-DockerNetworks
    if ($networks) {
        $networks | Format-Table -AutoSize
    }
}

function Initialize-DockerNetwork {
    param (
        [string]$NetworkName,
        [string]$Driver,
        [string]$Subnet,
        [string]$Gateway
    )
    
    Write-TimeLog "Setting up Docker network"
    
    Show-NetworkSetup
    
    # Check if network with same name, driver, subnet, and gateway already exists
    $existingNetworks = Get-DockerNetworks
    $matchingNetwork = $existingNetworks | Where-Object { 
        $_.Name -eq $NetworkName -and 
        $_.Driver -eq $Driver -and 
        $_.Subnet -eq $Subnet -and 
        $_.Gateway -eq $Gateway 
    }
    
    if ($matchingNetwork) {
        Write-TimeLog "Network '$NetworkName' with matching configuration already exists. Skipping creation."
        return
    }
    
    Remove-DockerNetworkByName -NetworkName $NetworkName
    
    Write-TimeLog "Creating network: $NetworkName"
    docker network create --driver $Driver --subnet=$Subnet --gateway=$Gateway $NetworkName
    ThrowIfError
    
    # Display subnet and gateway for the newly created network
    Show-NetworkSetup
}

function Start-BlockBuildUntilFileDeleted {
    param (
        [string]$FilePath
    )
    
    # Extract directory path from file path
    $directoryPath = Split-Path -Path $FilePath -Parent
    
    # Create the directory if it doesn't exist
    if (-Not (Test-Path $directoryPath)) {
        New-Item -Path $directoryPath -ItemType Directory -Force | Out-Null
        Write-TimeLog "Directory created: $directoryPath"
    }
    
    # Create the file if it doesn't already exist
    if (-Not (Test-Path $FilePath)) {
        New-Item -Path $FilePath -ItemType File -Force | Out-Null
        Write-TimeLog "File created: $FilePath"
    }
    else {
        Write-TimeLog "File already exists: $FilePath"
    }
    
    # Infinite loop while the file exists
    Write-TimeLog "Blocking build until file is deleted: $FilePath"
    while (Test-Path $FilePath) {
        Write-TimeLog "File exists, continuing loop..."
        Start-Sleep -Seconds 1  # Wait for 1 second before checking again
    }
    
    Write-TimeLog "File no longer exists. Exiting loop."
}

function Get-CommitMessage {
    # Try to get commit message from environment variables (CI/CD systems)
    $commitMessage = $null
    
    # Check common CI/CD environment variables
    if ($Env:APPVEYOR_REPO_COMMIT_MESSAGE_FULL) {
        $commitMessage = $Env:APPVEYOR_REPO_COMMIT_MESSAGE_FULL
    }
    elseif ($Env:BUILD_SOURCEVERSIONMESSAGE) {
        $commitMessage = $Env:BUILD_SOURCEVERSIONMESSAGE
    }
    elseif ($Env:GIT_COMMIT_MESSAGE) {
        $commitMessage = $Env:GIT_COMMIT_MESSAGE
    }
    else {
        # Fallback to git command
        try {
            $commitMessage = git log -1 --pretty=format:"%B" 2>$null
        }
        catch {
            Write-Warning "Could not retrieve commit message from git"
        }
    }
    
    return $commitMessage
}

function Test-BuildStopTag {
    param (
        [string]$Tag
    )
    
    $commitMessage = Get-CommitMessage
    if ($commitMessage -and $commitMessage -match "\[$Tag\]") {
        return $true
    }
    return $false
}

function Invoke-BuildStopIfTagged {
    param (
        [string]$Tag,
        [string]$StopPointName
    )
    
    if (Test-BuildStopTag -Tag $Tag) {
        Write-TimeLog "Build stop tag [$Tag] detected in commit message. Blocking at $StopPointName"
        $filePath = Join-Path -Path $Env:BUILD_TEMP -ChildPath "build_stop_$Tag.txt"
        Start-BlockBuildUntilFileDeleted -FilePath $filePath
        Write-TimeLog "Build stop released. Continuing build process"
    }
}

function Initialize-Directory {
    param (
        [string]$DirectoryPath
    )

    if (-Not (Test-Path -Path $DirectoryPath)) {
        New-Item -Path $DirectoryPath -ItemType Directory -Force | Out-Null
        Write-TimeLog "Directory created: $DirectoryPath"
    }
    else {
        Write-TimeLog "Directory already exists: $DirectoryPath"
    }
}

function Get-ContainerLogs {
    param (
        [string]$ContainerName,
        [int]$TailLines = 25
    )
    
    try {
        $logs = docker logs $ContainerName --tail $TailLines 2>&1
        return $logs
    }
    catch {
        Write-Warning "Could not retrieve logs from container '$ContainerName': $_"
        return $null
    }
}

function Invoke-PsCommandInContainer {
    param (
        [string]$ContainerName,
        [Parameter(Mandatory = $true)]
        [object]$Command  # Can be string or scriptblock
    )
    
    if ($Command -is [scriptblock]) {
        docker exec $ContainerName powershell $Command
    }
    else {
        docker exec $ContainerName powershell $Command
    }
    
    # Check for errors before calling ThrowIfError
    if ($LASTEXITCODE -ne 0) {
        Write-TimeLog "Command failed in container '$ContainerName'. Retrieving container logs..."
        $containerLogs = Get-ContainerLogs -ContainerName $ContainerName -TailLines 25
        if ($containerLogs) {
            Write-Host "---------------- CONTAINER LOGS (last 25 lines) ----------------" -ForegroundColor Red
            Write-Host ($containerLogs -join "`r`n")
            Write-Host "---------------- END CONTAINER LOGS ----------------" -ForegroundColor Red
        }
    }
    
    ThrowIfError
}

function Copy-FileFromContainer {
    param (
        [string]$ContainerName,
        [string]$ContainerPath,
        [string]$LocalPath
    )
    
    docker cp "${ContainerName}:${ContainerPath}" $LocalPath
    ThrowIfError
}

function Test-IsTagBuild {
    # Check various CI/CD environment variables to determine if this is a tag build
    # Azure Pipelines: Build.SourceBranch (passed as IMAGE_VERSION or available as BUILD_SOURCEBRANCH)
    if ($Env:BUILD_SOURCEBRANCH -and $Env:BUILD_SOURCEBRANCH -match '^refs/tags/') {
        return $true
    }
    # Check if IMAGE_VERSION contains refs/tags/ prefix (most reliable since we pass it explicitly)
    if ($Env:IMAGE_VERSION -and $Env:IMAGE_VERSION -match '^(?:refs?\/)?tags\/') {
        return $true
    }
    # GitLab CI
    if ($Env:CI_COMMIT_TAG) {
        return $true
    }
    # AppVeyor
    if ($Env:APPVEYOR_REPO_TAG -eq 'true') {
        return $true
    }
    # GitHub Actions
    if ($Env:GITHUB_REF -and $Env:GITHUB_REF -match '^refs/tags/') {
        return $true
    }
    return $false
}

function Test-TagBelongsToBranch {
    param (
        [string]$TagName,
        [string]$ExpectedBranch
    )
    
    try {
        # Fetch tags to ensure we have the latest (important in CI/CD environments)
        git fetch --tags 2>$null | Out-Null
        
        # Get the commit SHA that the tag points to
        $tagCommit = git rev-parse $TagName 2>$null
        if (-not $tagCommit -or $LASTEXITCODE -ne 0) {
            Write-Warning "Tag '$TagName' does not exist in the repository or could not be resolved"
            return $false
        }
        
        # Check if the tag's commit is reachable from the expected branch
        # Try both local and remote branch references
        $branchRefs = @(
            "refs/heads/$ExpectedBranch",
            "refs/remotes/origin/$ExpectedBranch",
            "origin/$ExpectedBranch",
            $ExpectedBranch
        )
        
        foreach ($branchRef in $branchRefs) {
            # Check if branch exists
            $branchExists = git rev-parse --verify $branchRef 2>$null
            if ($branchExists) {
                # Check if tag commit is an ancestor of the branch (or the branch contains the tag)
                git merge-base --is-ancestor $tagCommit $branchRef 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Validation passed: Tag '$TagName' (commit $tagCommit) belongs to branch '$ExpectedBranch'"
                    return $true
                }
            }
        }
        
        # Alternative: Check if branch contains the tag commit
        $branchesContainingCommit = git branch -a --contains $tagCommit 2>$null
        
        if ($branchesContainingCommit) {
            # Normalize branch names (remove refs/heads/, refs/remotes/origin/, etc.)
            $normalizedBranches = $branchesContainingCommit | ForEach-Object {
                $branch = $_.Trim()
                # Skip detached HEAD states
                if ($branch -match '\(HEAD detached') {
                    return $null
                }
                # Extract branch name from various formats
                if ($branch -match 'remotes/origin/(.+)') {
                    $matches[1]
                }
                elseif ($branch -match 'refs/remotes/origin/(.+)') {
                    $matches[1]
                }
                elseif ($branch -match 'refs/heads/(.+)') {
                    $matches[1]
                }
                elseif ($branch -match '^\*\s*(.+)') {
                    $matches[1]
                }
                else {
                    # Remove leading asterisk and whitespace, and any refs/ prefix
                    $branch -replace '^\*\s*', '' -replace '^\s+', '' -replace '^refs/[^/]+/', ''
                }
            } | Where-Object { $_ -ne '' -and $_ -ne $null } | Sort-Object -Unique
            
            # Check if expected branch is in the list (case-insensitive)
            $branchFound = $normalizedBranches | Where-Object { $_.ToLower() -eq $ExpectedBranch.ToLower() }
            
            if ($branchFound) {
                Write-Host "Validation passed: Tag '$TagName' belongs to branch '$ExpectedBranch'"
                return $true
            }
            else {
                Write-Warning "Validation failed: Tag '$TagName' does not belong to branch '$ExpectedBranch'"
                Write-Warning "Tag '$TagName' (commit $tagCommit) is found in branches: $($normalizedBranches -join ', ')"
                return $false
            }
        }
        else {
            Write-Warning "Tag '$TagName' (commit $tagCommit) is not found in any branch"
            return $false
        }
    }
    catch {
        Write-Warning "Error validating tag-branch relationship: $_"
        return $false
    }
}

function Get-ImageTag {
    param (
        [string]$ImageVersion,
        [string]$RegistryPath,
        [string]$ImageName = "sabentisplus"
    )
    
    Write-Host "Environment IMAGE_VERSION: $ImageVersion"
    Write-Host "Environment REGISTRY_PATH: $RegistryPath"
    
    $isTagBuild = Test-IsTagBuild
    Write-Host "Is tag build: $isTagBuild"
    
    # Clean up version string by removing Git-specific prefixes
    if ($ImageVersion -match '^(?:refs?\/)?(?:heads|tags|remotes|pull|merge-requests)\/(.+)$') {
        $ImageVersion = $matches[1]
        Write-Host "Image version adjusted to remove git specific prefixes: $ImageVersion"
    }
    
    # Ensure registry path ends with a slash
    if (-not $RegistryPath.EndsWith('/')) {
        $RegistryPath = "$RegistryPath/"
    }
    
    # For tag builds, enforce branch/semver format
    if ($isTagBuild) {
        # Validate and split version into repository path and tag (must be branch/semver format)
        if ($ImageVersion -match '^(.+)\/([^\/]+)$') {
            $repoPath = $matches[1]
            $imageTag = $matches[2]
            
            # Validate that the tag belongs to the specified branch
            $fullTagName = "$repoPath/$imageTag"
            if (-not (Test-TagBelongsToBranch -TagName $fullTagName -ExpectedBranch $repoPath)) {
                throw "Tag validation failed: Tag '$fullTagName' does not belong to branch '$repoPath'. Please ensure you are tagging from the correct branch."
            }
            
            # Validate semver format (supports v1.0.0, 1.0.0, 1.0.0.0, or with pre-release)
            if ($imageTag -match '^(v?\d+\.\d+\.\d+(\.\d+)?)(-.+)?$') {
                # Format: registry/branch/image-name:tag (RegistryPath already has trailing slash)
                $imageTagFull = "$RegistryPath$repoPath/$ImageName`:$imageTag"
                Write-Host "Image tag constructed: $imageTagFull"
                return $imageTagFull
            }
            else {
                throw "Invalid semver format for image tag. Expected format: branch/x.y.z or branch/vx.y.z or branch/x.y.z.w (e.g., sprint1/v1.0.0.0), but got: $ImageVersion"
            }
        }
        else {
            throw "Invalid image version format for tag build. Expected format: branch/semver (e.g., sprint1/v1.0.0), but got: $ImageVersion"
        }
    }
    else {
        # For non-tag builds (branch builds), use simpler format without validation
        # This allows builds to proceed without producing images for push
        Write-Host "Non-tag build detected. Using simplified image tag format."
        # Check if RegistryPath already ends with ImageName to avoid duplication
        $registryBase = $RegistryPath
        if ($registryBase.EndsWith("$ImageName/")) {
            $imageTagFull = "$registryBase$ImageVersion"
        }
        else {
            $imageTagFull = "$RegistryPath$ImageName`:$ImageVersion"
        }
        Write-Host "Image tag constructed: $imageTagFull"
        return $imageTagFull
    }
}