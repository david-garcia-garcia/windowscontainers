function SbsDownloadFile {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$Path,
        [string]$TmpFile
    )

    function convertFileSize {
        param(
            $bytes
        )

        if ($bytes -lt 1MB) {
            return "$([Math]::Round($bytes / 1KB, 2)) KB"
        }
        elseif ($bytes -lt 1GB) {
            return "$([Math]::Round($bytes / 1MB, 2)) MB"
        }
        elseif ($bytes -lt 1TB) {
            return "$([Math]::Round($bytes / 1GB, 2)) GB"
        }
    }

    Write-Verbose "URL set to ""$($Url)""."

    if (!($Path)) {
        Write-Verbose "Path parameter not set, parsing Url for filename."
        $URLParser = $Url | Select-String -Pattern ".*\:\/\/.*\/(.*\.{1}\w*).*" -List

        $Path = "./$($URLParser.Matches.Groups[1].Value)"
    }

    Write-Verbose "Path set to ""$($Path)""."

    #Load in the WebClient object.
    Write-Verbose "Loading in WebClient object."
    try {
        $Downloader = New-Object -TypeName System.Net.WebClient
    }
    catch [Exception] {
        Write-Error $_ -ErrorAction Stop
    }

    #Creating a temporary file.
    if ([string]::IsNullOrWhiteSpace($TmpFile)) {
        $TmpFile = New-TemporaryFile;
    }

    Write-Verbose "TmpFile set to ""$($TmpFile)""."

    try {

        #Start the download by using WebClient.DownloadFileTaskAsync, since this lets us show progress on screen.
        Write-Verbose "Starting download..."
        $FileDownload = $Downloader.DownloadFileTaskAsync($Url, $TmpFile)

        #Register the event from WebClient.DownloadProgressChanged to monitor download progress.
        Write-Verbose "Registering the ""DownloadProgressChanged"" event handle from the WebClient object."
        Register-ObjectEvent -InputObject $Downloader -EventName DownloadProgressChanged -SourceIdentifier WebClient.DownloadProgressChanged | Out-Null

        #Wait two seconds for the registration to fully complete
        Start-Sleep -Seconds 3

        if ($FileDownload.IsFaulted) {
            Write-Verbose "An error occurred. Generating error."
            SbsWriteError $FileDownload.GetAwaiter().GetResult()
            break
        }

        #While the download is showing as not complete, we keep looping to get event data.
        while (!($FileDownload.IsCompleted)) {

            if ($FileDownload.IsFaulted) {
                SbsWriteHost "An error occurred. Generating error.";
                SbsWriteError $FileDownload.GetAwaiter().GetResult();
                break;
            }

            $EventData = Get-Event -SourceIdentifier WebClient.DownloadProgressChanged | Select-Object -ExpandProperty "SourceEventArgs" -Last 1

            $ReceivedData = ($EventData | Select-Object -ExpandProperty "BytesReceived")
            $TotalToReceive = ($EventData | Select-Object -ExpandProperty "TotalBytesToReceive")
            $TotalPercent = $EventData | Select-Object -ExpandProperty "ProgressPercentage"

            $message = "Downloading File ($($TotalPercent)%) Downloaded $(convertFileSize -bytes $ReceivedData) / $(convertFileSize -bytes $TotalToReceive)";
            SbsWriteHost $message;
            Start-Sleep -Seconds 5;
        }
    }
    catch [Exception] {
        $ErrorDetails = $_

        switch ($ErrorDetails.FullyQualifiedErrorId) {
            "ArgumentNullException" { 
                Write-Error -Exception "ArgumentNullException" -ErrorId "ArgumentNullException" -Message "Either the Url or Path is null." -Category InvalidArgument -TargetObject $Downloader -ErrorAction Stop
            }
            "WebException" {
                Write-Error -Exception "WebException" -ErrorId "WebException" -Message "An error occurred while downloading the resource." -Category OperationTimeout -TargetObject $Downloader -ErrorAction Stop
            }
            "InvalidOperationException" {
                Write-Error -Exception "InvalidOperationException" -ErrorId "InvalidOperationException" -Message "The file at ""$($Path)"" is in use by another process." -Category WriteError -TargetObject $Path -ErrorAction Stop
            }
            Default {
                Write-Error $ErrorDetails -ErrorAction Stop
            }
        }
    }
    finally {
        #Cleanup tasks
        Write-Verbose "Cleaning up...";
        Write-Progress -Activity "Downloading File" -Completed;
        Unregister-Event -SourceIdentifier WebClient.DownloadProgressChanged;

        if (($FileDownload.IsCompleted) -and !($FileDownload.IsFaulted)) {
            #If the download was finished without termination, then we move the file.
            Write-Verbose "Moved the downloaded file to ""$($Path)"".";
            if ($TmpFile -ne $Path) {
                Move-Item -Path $TmpFile -Destination $Path -Force;
            }
        }
        else {
            #If the download was terminated, we remove the file.
            Write-Verbose "Cancelling the download and removing the tmp file.";
            $Downloader.CancelAsync();
            Remove-Item -Path $TmpFile -Force;
        }

        $Downloader.Dispose();
    }
}