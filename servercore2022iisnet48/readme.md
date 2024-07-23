# Base image for IIS Setups for hosting ASP.NET applications

Inherits behaviours from these other images:

* [Server Core 2022](../servercore2022/readme.md) 
* [Server Core 2022 IIS](../servercore2022iis/readme.md) 

Add the New Relic APM, the image has a default configuration in:

```powershell
C:\ProgramData\New Relic\.NET Agent\newrelic.config
```

You can set the license key through environment:

```
NEW_RELIC_LICENSE_KEY
```

or completely override the default configuratoin using a configmap.

