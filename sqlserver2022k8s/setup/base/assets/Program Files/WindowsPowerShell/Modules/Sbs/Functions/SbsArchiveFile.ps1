function SbsArchiveFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$filePath
    )

    $directory = [System.IO.Path]::GetDirectoryName($filePath);
    $filenameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($filePath);

    $backupFileName = "$filenameWithoutExtension.yaml.bak";
    $counter = 0;

    $backupFilePath = Join-Path -Path $directory -ChildPath $backupFileName;

    while (Test-Path $backupFilePath) {
        $backupFileName = "$filenameWithoutExtension.yaml.$counter.bak";
        $backupFilePath = Join-Path -Path $directory -ChildPath $backupFileName;
        $counter++;
    }

    Rename-Item -Path $filePath -NewName $backupFileName;
}

