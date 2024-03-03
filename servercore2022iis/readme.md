# Base image for IIS Setups

Inherits behavior from these other images:

* [Microsoft Sever Core 2022](../servercore2022/readme.md) 

Enables the Web Server Role and installs:

* [Chocolatey Software | URL Rewrite for IIS (Install) 2.1.20190828](https://community.chocolatey.org/packages/UrlRewrite)
* [Chocolatey Software | IIS Application Request Routing (Install) 3.0.20210521](https://community.chocolatey.org/packages/iis-arr)

The following IIS features are enabled:

* IIS-HttpRedirect
* IIS-HealthAndDiagnostics
* IIS-RequestFiltering
* IIS-CertProvider
* IIS-HttpCompressionDynamic
* IIS-HttpCompressionStatic
* IIS-ApplicationInit
* IIS-IpSecurity
* IIS-LoggingLibraries
* IIS-RequestMonitor
* IIS-HttpTracing
* IIS-StaticContent
* IIS-CGI

Just in case you need to setup TLS termination directly in the container, unsafe cyphers are disabled, plus Central Certificate Store is configured.

## IIS Remote Administration

Container is prepared for IIS Remote Administration.

This service is disabled by default, to enable during container startup automatically:

```powershell
SBS_SRVENSURE=WMSVC
```

You need to install this on your VM to connect:

[Chocolatey Software | Microsoft IIS Manager for Remote Administration 1.2.0](https://community.chocolatey.org/packages/inetmgr)

### To remote admin for docker

Get the container's IP address

```
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' {container_name_or_id}
```

Set credentials

```powershell
docker exec -it {container_name_or_id} powershell
net user localadmin {password}
```

### To remote admin for kubernetes

Open a terminal to the pod and change the localadmin password

```
kubectl exec -it app-c8bf54b49-5h9tt -- powershell
net user localadmin {password}
```

Redirect the IIS Remote admin port

```powershell
kubectl port-forward {pod} 8172:8172 --address 192.168.68.4
```

**Important**: you will not be able to connect to IIS from within the same machine where the port is bound. IIS remote manager detects that the destination IP is also bound to the local computer and will skip remote management completely. There is no way to workaround this (not changing ports, not using HOSTS to fake a different hostname). The only way to make is to connect from somewhere where the IP does not match the one used for port forwarding. You can spin up a VM inside HyperV and from there, access the forwarded port in your host.

![image-20240117144908714](readme_assets/img-remoteiis-hyperv)

## Remote debugging

```powershell
choco install visualstudio2022-remotetools -y

# This will setup remote open and public debugging. Do this at your own risk. If done under proper conditions, it is totally safe.
msvsmon.exe /noauth /anyuser /silent /nostatus /noclrwarn /nosecuritywarn /nofirewallwarn /nowowwarn /fallbackloadremotemanagedpdbs /timeout:2147483646
```

## Passing environment variables to IIS

Use SBS_IISENV to propagate environment variables from the container to IIS applications.

Example:

```yaml
SBS_IISENV=POOLREGEX:ENVREGEX#POOLREGEX2:ENVREGEX2
```

So if you want to propagate all environment variable to all pools:

```
SBS_IISENV=.*:.*
```

**NOTE**: Make sure that you are correctly NOT setting your pool to autostart automatically with iis, but to do so as part of the entrypoint setup. Otherwise you risk these env settings being added to the pool before the pools starts, which will require a manual pool restart to make them visible to the application.

## Adding pools to user groups

Use SBS_ADDPOOLSTOGROUPS to add application pool identities to local groups.

Specify a list of groups where **all** application pool identities will be added to. You can either use friendly group name, or the group SID (recommended for well known groups).

This adds pools to Performance Monitor and Performance Log users.

```yaml
SBS_ADDPOOLSTOGROUPS=S-1-5-32-558,S-1-5-32-559
```

## Automatic Certificate Generation

The image incorporates functionality for autonomously and centrally managing TLS termination, as well as the provisioning of certificates through Let's Encrypt using IIS Central Certificate Store, supporting load balancing.

Certificate provisioning and management is done with:

[david-garcia-garcia/iischef (github.com)](https://github.com/david-garcia-garcia/iischef)

In production environments, the recommendation is to use TLS terminations at access points (WAF/FW) or native certificate providers such as K8S's Cert Manager.

This functionality is part of the image to:

* Facilitate debugging and diagnosis of applications in development, eliminating the need to provision separate entry points (which becomes complicated because this is a Windows image and mixing Windows and Linux images is not possible at the same time with Docker Desktop)
* Ensure we have an emergency mechanism to autonomously manage TLS terminations. Thanks to this mechanism, it is possible to expose a K8S service directly through a LoadBalancer and have self-managed TLS terminations.

Certificate provisioning is done automatically when the container starts if the provider is "SelfSigned". For other providers, there is a scheduled task that checks the state of the certificates every 1 minute and provisions new ones if necessary, for domain names recently linked to environments it may be necessary to wait a few minutes for the certificate to be provisioned.

The configuration of the automatic certificate renewal behavior is done through environment variables.

**SBS_AUTOSSLHOSTNAMES**

Domain names whose certificates should be provisioned, separated by ";".

**SBS_AUTOSSLPASSWORD**

Password for the PFX of the certificates

**SBS_AUTOSSLPROVIDER**

Certificate provider, can be one of:

	* SelfSigned (Self-signed)
	* AcmeStaging (ACME testing)
	* Acme (ACME production)

**SBS_AUTOSSLCSSPATH**

Path inside the container where certificates, verification challenges, and secrets related to certificate renewal will be stored. It is important that this storage is shared and persisted across all nodes in a multi-front-end web environment (for example in Kubernetes).

**If this is left empty, automatic certificate provisioning and CCS will not be initialized.**

**SBS_AUTOSSLACCOUNTEMAIL**

Email address for registration with the certification authority.

**SBS_AUTOSSLTHRESHOLD**

Threshold for automatic SSL certificate renewal in days. Certificates that are going to expire in less time than defined here will be automatically renewed. The machine has a scheduled task to renew and check the state of the certificates every 60 minutes.

**SBS_AUTOSSLSITESYNC**

When using SNI and CCS for SSL certificate distribution, it is necessary for the IIS website to have the HOSTNAMES of the domain certificates configured. Use this option to indicate the name of the IIS Site whose SSL bindings will be synchronized with the array of certificates in the Central Certificate Store's certificate directory.

When set, this option will periodically inspect all the certificates in the CCS store, and and the corresponding SSL bindings to the specified website.

**Example configuration**

```yaml
- SBS_AUTOSSLHOSTNAMES=mywebsiste.com;testthesite.com;www.mysiste.net
- SBS_AUTOSSLPASSWORD=pfxpassword
- SBS_AUTOSSLPROVIDER=SelfSigned
- SBS_AUTOSSLCSSPATH=c:\certificates
- SBS_AUTOSSLACCOUNTEMAIL=foo@foo.com
- SBS_AUTOSSLTHRESHOLD=20
- SBS_AUTOSSLSITESYNC=Default Web Site
```

