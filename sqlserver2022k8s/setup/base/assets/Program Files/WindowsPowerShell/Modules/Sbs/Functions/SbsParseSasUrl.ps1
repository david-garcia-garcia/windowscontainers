function SbsParseSasUrl {
    param (
        [parameter(Mandatory = $true)]
        [string]$Url
    )

    if ([string]::isNullOrWhiteSpace($Url)) {
        return $null
    }

    $uri = New-Object System.Uri($Url)
    $storageAccountName = $uri.Host.Split('.')[0];
    $pathSegments = $uri.AbsolutePath.Trim('/').Split('/');
    $containerName = $pathSegments[0];
    $prefix = if ($pathSegments.Length -gt 1) { ($pathSegments | Select-Object -Skip 1) -join "/" } else { "" }
    $sasToken = $uri.Query.TrimStart('?')
    $baseUrl = "$($uri.Scheme)://$($uri.Host)/$containerName"

    return @{
        storageAccountName = $storageAccountName
        url                = $Url
        container          = $containerName
        baseUrl            = $baseUrl
        baseUrlWithPrefix  = "$($baseUrl)/$($prefix)"
        sasToken           = $sasToken
        prefix             = $prefix
    }
}