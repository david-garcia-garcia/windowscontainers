# Create website entrypoint
mkdir "c:\inetpub\wwwroot\OLAP"
xcopy /E /Y "C:\Program Files\Microsoft SQL Server\MSAS16.MSSQLSERVER\olap\bin\isapi" "c:\inetpub\wwwroot\OLAP"

Import-Module WebAdministration

# Change the physical path of the Default Web Site
Set-ItemProperty -Path "IIS:\Sites\Default Web Site" -Name physicalPath -Value "C:\inetpub\wwwroot\OLAP"

# Enable Basic Authentication for the Default Web Site
Set-WebConfigurationProperty -filter /system.webServer/security/authentication/basicAuthentication -name enabled -value True -PSPath IIS:\ -location 'Default Web Site'

# Disable Anonymous Authentication
Set-WebConfigurationProperty -filter /system.webServer/security/authentication/anonymousAuthentication -name enabled -value False -PSPath IIS:\ -location 'Default Web Site'

# Unlock the handlers section
& "$env:windir\system32\inetsrv\appcmd.exe" unlock config -section:system.webServer/handlers

# Add the handler
$extensionPath = "c:\inetpub\wwwroot\OLAP\msmdpump.dll"

Add-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST/Default Web Site' `
-filter "system.webServer/handlers" -name "." `
-value @{
    path = '*.dll';
    verb = '*';
    modules = 'IsapiModule';
    scriptProcessor = $extensionPath;
    resourceType = 'Unspecified';
    name = 'OLAP'
}

Add-WebConfiguration -Filter "system.webServer/security/isapiCgiRestriction" -Value @{description='My ISAPI Extension'; path=$extensionPath; allowed=$true} -PSPath 'IIS:\'
