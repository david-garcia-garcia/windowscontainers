# Este es el tema... después de muchas pruebas y debido a las características
# de algunas aplicaciones, lo que he decidido hacer es que en los contendores
# los pools están parados por defecto, y debe ser el entrypoint el que se encargue
# de arrancarlos. Por este motivo:
# El entry point se encarga de propagar lo que está en el ENV hacia la configuración de aplicación. Eso significa
# que la aplicación empieza a arrancar antes de estar configurada. Corremos el riesgo de que no pille las
# configuraciones, o incluso peor, aplicaciones que tardan una barbaridad en arrancar como prime, tengan que detener
# su arranque para volver a arrancar con una nueva configuración.

Import-Module WebAdministration;

# Set W3SVC service to automatic startup and start it
Set-Service -Name W3SVC -StartupType Automatic;
Start-Service -Name W3SVC;
SbsWriteHost "W3SVC service set to automatic and started";

# Start all IIS application pools
Get-IISAppPool | Where-Object { $_.State -eq 'Stopped' } | ForEach-Object {
    $poolName = $_.Name;
    $poolPath = "IIS:\AppPools\" + $poolName;
    $pool = Get-Item $poolPath;
    $pool.autoStart = $true;
    $pool.startMode = 'AlwaysRunning';
    $pool | Set-Item;
    Start-WebAppPool -Name $poolName;
    SbsWriteHost "Started Application Pool $poolName";
}

# Start all IIS sites
Get-Website | Start-Website;

# Output a message indicating that sites and pools have been started
SbsWriteHost "All IIS sites and application pools have been started.";
