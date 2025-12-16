$ErrorActionPreference = 'Stop'

Write-Host "Downloading MinGW-w64 (portable)..."
# WinLibs provides portable GCC builds - no installer needed
$mingwUrl = "https://github.com/brechtsanders/winlibs_mingw/releases/download/14.2.0posix-19.1.1-12.0.0-ucrt-r2/winlibs-x86_64-posix-seh-gcc-14.2.0-mingw-w64ucrt-12.0.0-r2.zip"
$mingwZip = "C:\mingw.zip"
$mingwDir = "C:\mingw64"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $mingwUrl -OutFile $mingwZip
Expand-Archive -Path $mingwZip -DestinationPath "C:\" -Force

Write-Host "Compiling wait.exe with GCC..."
$gccExe = "C:\mingw64\bin\gcc.exe"
& $gccExe -O2 -s -o C:\wait.exe C:\src\wait.c -lkernel32

if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path "C:\wait.exe")) {
    throw "wait.exe was not created"
}

$size = (Get-Item "C:\wait.exe").Length
Write-Host "wait.exe compiled successfully (size: $size bytes)"
