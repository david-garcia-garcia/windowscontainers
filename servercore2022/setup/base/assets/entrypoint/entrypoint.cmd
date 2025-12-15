@echo off
REM Lightweight CMD entrypoint that calls PowerShell entrypoint in CmdMode
REM This reduces memory footprint from ~118MB (PowerShell) to ~4MB (CMD)
REM In CmdMode, shutdown listeners and main service loop are disabled

REM Check if command arguments were provided before calling PowerShell
set "HAS_ARGS=0"
if not "%~1"=="" (
    set "HAS_ARGS=1"
)

REM Call PowerShell entrypoint in CmdMode, passing through any arguments
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\entrypoint\entrypoint.ps1" -CmdMode %*

REM Check if PowerShell exited with an error (non-zero exit code)
if errorlevel 1 (
    exit /b %errorlevel%
)

REM If command arguments were provided, execute them directly in CMD (more efficient than PowerShell)
REM The executed command will hold the process - no need for an infinite wait loop
if "%HAS_ARGS%"=="1" (
    %*
    exit /b %errorlevel%
)

REM No arguments provided - exit (user should provide a command if they want to hold the process)
exit /b 0
