function SbsParseSasUrl {
    param (
        [string]$Url
    )

    if ([string]::isNullOrWhiteSpace($Url)) {
        return $null
    }

    $uriParts = $Url -split '\?'
    $baseUrl = $uriParts[0]
    $sasToken = $uriParts[1]
    $storageAccount = ($baseUrl -split '://')[1].Split('.')[0]
    $container = ($baseUrl -split '/')[3]
    $credentialName = "https://$storageAccount.blob.core.windows.net/$container"

    return @{
        url            = $Url
        container      = $container
        credentialName = $credentialName
        baseUrl        = $baseUrl
        sasToken       = $sasToken
    }
}