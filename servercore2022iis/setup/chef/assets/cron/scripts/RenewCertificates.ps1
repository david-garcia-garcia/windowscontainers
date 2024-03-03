# Read environment variables
$hostNames = [System.Environment]::GetEnvironmentVariable("SBS_AUTOSSLHOSTNAMES");
$provider = [System.Environment]::GetEnvironmentVariable("SBS_AUTOSSLPROVIDER");
$mail = [System.Environment]::GetEnvironmentVariable("SBS_AUTOSSLACCOUNTEMAIL");
$threshold = [System.Environment]::GetEnvironmentVariable("SBS_AUTOSSLTHRESHOLD");

if (![string]::IsNullOrWhiteSpace($hostNames)) {
  
    # Make sure we are able to resolve ACME challenges.
    Invoke-IISChefSetupAcmeChallenge;

    # Split hostnames by semicolon
    $hostNamesArray = $hostNames -split ";";

    # Iterate through each hostname and invoke the command
    foreach ($hostname in $hostNamesArray) {
        Invoke-IISChefGetCert -Hostname $hostname -Provider $provider -RenewThresholdDays $threshold -RegistrationMail $mail;
    }
}

$siteSync = [System.Environment]::GetEnvironmentVariable("SBS_AUTOSSLSITESYNC");

if (![string]::IsNullOrWhiteSpace($siteSync)) {
  Invoke-IISChefSyncCertsToSite -SiteName $siteSync;
}