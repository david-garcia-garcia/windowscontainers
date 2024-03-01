# Server Core 2022 Base Image with basic tooling

This image extends the base Server Core 2022 image with some preinstalled software, configurations and an **extensible entrypoint setup**. One of the major issues when preparing windows containers is proper orchestration of startup and shutdown in different layers (as you stack container images) and proper and reliable handling of the lifecycle of a container (startup and shutdown).

## Preinstalled software and configurations

* Chocolatey ([Chocolatey Software | Chocolatey - The package manager for Windows](https://chocolatey.org/))
* 7zip ([Chocolatey Software | 7-Zip (Install) 23.1.0](https://community.chocolatey.org/packages/7zip.install))
* Nuget package provider for Powershell
* Powershell-yaml ([cloudbase/powershell-yaml: PowerShell CmdLets for YAML format manipulation (github.com)](https://github.com/cloudbase/powershell-yaml))
* Log Source for event viewer "ContainerLifecycle" in the "Application" category
* Enabled Long Path Support through windows registry
* Disable IEEnhancedSecurity through windows reigstry
* Enabled Session events auditing to Event Viewer
* Creates a "localadmin" account with a random password

## Log monitor and EntryPoint

Default entrypoint for this image is LogMonitor, which in turn starts the c:\entrypoint\entrypoint.ps1 script.

[windows-container-tools/LogMonitor/README.md at main · microsoft/windows-container-tools (github.com)](https://github.com/microsoft/windows-container-tools/blob/main/LogMonitor/README.md)

To fine-tune what logs are being monitored, refer to the LogMonitor documentation.

If you don't want to use LogMonitor as the entrypoint just add this in your image:

```powershell
CMD ["powershell.exe", "-File", "C:\\entrypoint\\entrypoint.ps1" ]
```

**WARNING**: Log monitor is an excellent tool for debugging while setting up your containers, but a terrible companion for production loads. The lack of configuration options, plus several bugs that interfere with the container shutdown when timeouts have been expanded make it a dangerous choice for production workloads. Find another way of moving your logging information out of the container.

## Log rotation

A unix style logrotation utility is installed https://github.com/theohbrothers/Log-Rotate and runs every day at 3AM.

You can place your log rotation custom configurations using a unix like style

```powershell
c:\logrotate\log-rotate.d
```

## Scheduled Tasks

If you need to deploy scheduled tasks into the container, you can copy the XML definition of the task into:

```powershell
c:\cron\definitions
```

and they will be automatically setup/updated when the container boots. If you need any of the tasks to run inmediately on boot, use the *SBS_CRONRUNONBOOT* environment variable to define a commad separated list of scheduled tasks to run on boot.

If you want make sure you properly have traceability of scheduled task failures, whatever you run in the scheduled task make sure is invoked through the helper script provided in the image:

```xml
<Exec>
   <Command>C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe</Command>
   <Arguments>-File "c:\cron\runscript.ps1" -path "c:\cron\scripts\logrotaterun.ps1"	    </Arguments>
</Exec>
```

This script treats errors and logs calls to the scheduled task on the Application::ContainerLifecycle event source. In case of error, the event code 23003 is added. You can use this to monitor scheduled task behaviours on an external logging system.

## Startup and shutdown

Container startup and shutdown are somewhat tricky to get right. With this image, the entrypoint executes a lifecycle managing script.

It will first run all the powershell scripts it finds in:

```powershell
c:\entrypoint\init
```

When shutting down the container it will run all the scripts in:

```powershell
c:\entrypoint\shutdown
```

This might sound simple, but it helps you handle several non-trivial behaviors in the container lifecycle.

In both cases, the scripts in those folders are run in their alphabetical order. You will se that the included init and shutdown scripts have numerical prefixes to aid in being able to inject startup or shutdown scripts with ease at any point:

```powershell
0000_SetTimezone.ps1
0300_StartServices.ps1
0999_StartScheduledTasks
```

By default the init scripts are run synchronously, if you want to run them through a Job, use the SBS_ENTRYPOINTRYNASYNC environment variable. Running them sincrhonously is usually much fater, but remember that Powershell will lock assemblies that have been loaded in to the script. Using the asynchronous mode will prevent this from happening as the assemblies are released when the initialization job is over.

To check for container readyness the entrypoint script will write a "ready" file to the c:\ drive, so you can check in K8S if the container has been through the setup process:

```YAML
startup_probe {
  exec {
    command = ["cmd.exe", "/c", "IF EXIST C:\\ready (echo 'c:\\ready found' && exit 0 ) ELSE (echo 'c:\\ready not found' && exit 1 )"]
  }
  initial_delay_seconds = 10
  period_seconds        = 4
  failure_threshold     = 20
}
```

Note that if you are using docker and starting/stopping the same image, the image state is preserved  so this readyness approach will only work reliably for K8S where the container starts always from a pristine state. The teardown process will attempt to delete the ready flag, so it should also works in docker as an indication the the startup scripts have completed.

For shutdown scripts please consider the following important information: inside a windows container - by default - it is complex and tricky to setup shutdown logic that keeps the image running until you are done. Read this: [Unable to react to graceful shutdown of (Windows) container · Issue #25982 · moby/moby (github.com)](https://github.com/moby/moby/issues/25982)

To deal with this, this image overrides the default process shutting down timeout boosting it to 30 minutes versus the default 5 seconds.

```powershell
RUN reg add hklm\system\currentcontrolset\services\cexecsvc /v ProcessShutdownTimeoutSeconds /t REG_DWORD /d 1800
RUN reg add hklm\system\currentcontrolset\control /v WaitToKillServiceTimeout /t REG_SZ /d 1800000 /f
```

This means that a missconfiguration or missbehaviour during shutdown can leave your container held for up to 30 minutes until it is forcefully shutdown. It also means that **any dangling process** opened by the container manager (i.e. containerd) (such as a remote console in either K8S or docker) will keep your container from being freed. To deal with this, we assume that the entry point should be the only source of shutdown blocking, and anything that needs to be shutdown gracefully should be dealt with in the entry point. The entry point will forcefully close these danging processes if any, this is controlled through the enviornment variable:

```powershell
SBS_SHUTDOWNCLOSEPROCESSES=cmd,powershell,pwsh,logmonitor
```

If none specified, defaults to "cmd,powershell,pwsh".

**Handling shutdown in Kubernetes**

[Container Lifecycle Hooks | Kubernetes](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/)

All the previous setup is to provide a consistent and controlled shutdown experience in docker. In K8S, they have specific ways to deal with shutdown through the PreStop hook.

If you publish this container image to a K8S environment, you need to tweak the ENV settings in the following way:

```yaml
# Do not shutdown as part of the entrypoint lifecycle, as this is being handled in the preStop hook
SBS_AUTOSHUTDOWN=0
# Do close dangling processes
SBS_SHUTDOWNCLOSEPROCESSES=cmd,powershell,pwsh,logmonitor
```

Then setup the preStop hook for K8S:

```YAML
lifecycle {
  pre_stop {
     exec {
       command = ["powershell.exe", "-File", "c:\\entrypoint\\shutdown.ps1"]
     }
   }
}
```

## New Relic and NRI Perfmon

The image comes pre-installed with New Relic NRI (Infrastructure) and Perfmon ([newrelic/nri-perfmon: Windows Perfmon / WMI On-Host Integration for New Relic Infrastructure (github.com)](https://github.com/newrelic/nri-perfmon)).

The second is just an extension for the NRI agent to collect Performance Counters.

The service is stopped and needs to be configured if you want it to be started.

```
# Ensure the new relic service starts with the container as it is disabled by default
SBS_SRVENSURE=newrelic-infra
# Add the new relic license key
NEW_RELIC_LICENSE_KEY=MYLICENSEKEY
```

## Time Zone

To set the container time zone during startup:

```powershell
SBS_CONTAINERTIMEZONE=Pacific Standard Time
```

## Automatically start services

Some services are disabled by default in the image. To start them up with the container:

```
SBS_SRVENSURE=newrelic-infra,service2,service3
```

