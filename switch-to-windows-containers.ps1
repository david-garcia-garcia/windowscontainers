# Switch to Windows Containers mode
# This script ensures Docker is running in Windows containers mode

. .\bootstraptest.ps1

# Ensure we are in Windows containers mode
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

    if ($currentContext -ne "desktop-windows")
    {
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

