function SbsParseSasUrl {
    param (
        [parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $null;
    }

    if (-not ($Url -match "^http")) {
        return $null;
    }

    Add-Type -AssemblyName System.Web;

    $uri = New-Object System.Uri($Url)
    $storageAccountName = $uri.Host.Split('.')[0];
    $pathSegments = $uri.AbsolutePath.Trim('/').Split('/');
    $containerName = $pathSegments[0];
    $prefix = if ($pathSegments.Length -gt 1) { ($pathSegments | Select-Object -Skip 1) -join "/" } else { "" }
    $sasToken = $uri.Query.TrimStart('?')
    $baseUrl = "$($uri.Scheme)://$($uri.Host)/$containerName"

    # Parse the query string for additional parameters
    $queryString = [System.Web.HttpUtility]::ParseQueryString($uri.Query)
    
    # Attempt to convert dates from string to DateTime objects
    $signedExpiry = [DateTime]::MinValue
    $startTime = [DateTime]::MinValue

    if ($null -ne $queryString["se"]) {
        [DateTime]::TryParseExact($queryString["se"], "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$signedExpiry) | Out-Null
    }
    if ($null -ne $queryString["st"]) {
        [DateTime]::TryParseExact($queryString["st"], "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$startTime) | Out-Null
    }

    if ($signedExpiry -eq [DateTime]::MinValue) {
        $signedExpiry = $null
    }

    if ($startTime -eq [DateTime]::MinValue) {
        $startTime = $null
    }

    return @{
        storageAccountName = $storageAccountName
        url                = $Url
        container          = $containerName
        baseUrl            = $baseUrl
        baseUrlWithPrefix  = "$($baseUrl)/$($prefix)"
        sasToken           = $sasToken
        prefix             = $prefix
        signedExpiry       = $signedExpiry
        startTime          = $startTime
        permissions        = $queryString["sp"]
        signedResource     = $queryString["sr"]
        signedProtocol     = $queryString["spr"]
        signedVersion      = $queryString["sv"]
    }
}