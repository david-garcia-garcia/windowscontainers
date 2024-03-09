$certStorePath = [System.Environment]::GetEnvironmentVariable("SBS_AUTOSSLCSSPATH");

# Configurar el Central Certificate Store
if (![string]::IsNullOrWhiteSpace($certStorePath)) {

    # DECODE PASSWORD
    Add-Type -AssemblyName System.Security;
    $password = [System.Environment]::GetEnvironmentVariable("SBS_AUTOSSLPASSWORD");
    if ([string]::IsNullOrWhiteSpace($password)) {
        throw "SBS_AUTOSSLPASSWORD env not provided. In order to setup CCS through SBS_AUTOSSLCSSPATH you must provide a PFX password.";
    }
    $password = [Convert]::FromBase64String($password);
    $password = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($password, $null, 'LocalMachine'));

    SbsWriteHost "Initializing Central Certificate Store in Image";
    Invoke-IISChefSetupCcs -CertStoreLocation $certStorePath -PrivateKeyPassword $password;
}

# Esto nos interesa hacerlo ya y de manera síncrona porque en caso de que ya tuvieramos
# certificados disponibles en el storage, no haría falta esperar para que estén funcionando
# a través de la tarea programada
$siteSync = [System.Environment]::GetEnvironmentVariable("SBS_AUTOSSLSITESYNC");

if (![string]::IsNullOrWhiteSpace($siteSync)) {
    Invoke-IISChefSyncCertsToSite -SiteName $siteSync;
}