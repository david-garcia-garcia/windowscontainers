Get-ChildItem -Path "C:\ProgramData\New Relic\.NET Agent\Logs" -Filter "*.log" |
Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
ForEach-Object {
    try {
        Remove-Item $_.FullName -Force;
    }
    catch {
        Write-Warning "Failed to delete file: $($_.FullName). It may be in use.";
    }
}
