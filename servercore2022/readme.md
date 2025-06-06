# Server Core 2022 Base Image with basic tooling

This image extends the base Server Core 2022 image with some preinstalled software, configurations and an **extensible entrypoint setup**. One of the major issues when preparing windows containers is proper orchestration of startup and shutdown in different layers (as you stack container images) and proper and reliable handling of the lifecycle of a container (startup and shutdown).

## Image configuration Cheat Sheet

### Environment variables

| Name                       | Default Value       | Hot reload supported | Description                                                  |
| -------------------------- | ------------------- | -------------------- | ------------------------------------------------------------ |
| SBS_CONTAINERTIMEZONE      | $null               | Yes                  | Container Timezone                                           |
| SBS_PROMOTE_ENV_REGEX      | $null               | Yes                  | When an environment variable matches this regular expression, it is promoted to system level. Careful with sensitive data. |
| XXX_PROTECT                | N/A                 | Yes                  | When an environment variable ends in _PROTECT it is encoded with DPAPI at the machine level, and the suffix removed. |
| SBS_INITASYNC              | $false              | N/A                  | Run initialization scripts in their own JOB.                 |
| SBS_SHUTDOWNTIMEOUT        | 15                  | Yes                  | Container shutdown timeout in seconds.                       |
| SBS_ENTRYPOINTERRORACTION  | Stop                | No                   | Set to "Continue" if you are debugging a container and want the container to start even if there are errors during initialization |
| SBS_SHUTDOWNCLOSEPROCESSES | cmd,powershell,pwsh | Yes                  | List of processes that will be terminated when shutdown has completed |
| SBS_SRVENSURE              | $null               | No                   | List of comma separated service names to start and enabled (Automatic startup) when the image starts |
| SBS_SRVSTOP                | $null               | Yes                  | List of comma separated service names to ensure are gracefully stopped when the container is stopped |
| SBS_CRON_{SCHEDULEDTASK}   | N/A                 | Yes                  | Use this to configure the trigger for a scheduled task that is already present inside the image. |
| CREATEDIR_{NAME}           | N/A                 | No                   | Automatically creates the specified directory during container initialization. Example: CREATEDIR_LOGS=C:\App\Logs |
| WER_ENABLE                 | $false              | No                   | Enable Windows Error Reporting configuration                 |
| WER_DUMPFOLDER             | $null               | No                   | Directory path for crash dump files                          |
| WER_DUMPCOUNT              | 4                   | No                   | Maximum number of dump files to keep                         |
| WER_DUMPTYPE               | 2                   | No                   | Type of dump to create (0=Custom, 1=Mini, 2=Full)           |
| WER_CUSTOMDUMPFLAGS        | 0                   | No                   | Custom dump flags for WER configuration                      |

Relevant locations

| Path                                                     | Usage                                                        |
| -------------------------------------------------------- | ------------------------------------------------------------ |
| c:\environment.d\**.json                                 | Provide environment variables as a json                      |
| c:\entrypoint\init\                                      | Path for initialization scripts                              |
| c:\entrypoint\refreshenv\                                | Path for scripts run after the env configuration is refreshed |
| c:\entrypoint\shutdown\                                  | Path for shutdown scripts                                    |
| c:\logrotate\log-rotate.d\                               | Path for log rotation scripts                                |
| c:\logmonitor\config.json                                | Default location for the LogMonitor configuration file.      |
| c:\ProgramFiles\WindowsPowerShell\Modules\Sbs\Functions\ | Path to custom autoloaded Powershell functions               |

## Preinstalled software and configurations

* Chocolatey ([Chocolatey Software | Chocolatey - The package manager for Windows](https://chocolatey.org/))
* 7zip ([Chocolatey Software | 7-Zip (Install) 23.1.0](https://community.chocolatey.org/packages/7zip.install))
* Nuget package provider for Powershell
* Log Source for event viewer "SbsContainer" in the "Application" category
* Enabled Long Path Support through windows registry
* Disable IEEnhancedSecurity through windows reigstry
* Enabled Session events auditing to Event Viewer
* Creates a "localadmin" account with a random password
* OpenSSH server (Windows Implementation)

## Entry Point

Default Entry Point for this image is the c:\entrypoint\entrypoint.ps1 script.

```powershell
CMD ["powershell.exe", "-File", "C:\\entrypoint\\entrypoint.ps1" ]
```

The entrypoint will execute all scripts located at:

```bash
c:\entrypoint\init
```

You can place here your own bootstrap scripts.

## Log Monitor

Container log output is managed using Microsoft's Log Monitor:

[windows-container-tools/LogMonitor/README.md at main · microsoft/windows-container-tools (github.com)](https://github.com/microsoft/windows-container-tools/blob/main/LogMonitor/README.md)

```powershell
CMD ["C:\\LogMonitor\\LogMonitor.exe", "/CONFIG", "c:\\logmonitor\\config.json", "powershell.exe", "-File", "C:\\entrypoint\\entrypoint.ps1" ]
```

The Log Monitor configuration is read from:

```
c:/logmonitor/config.json 
```

This allows you to directly mount the Log Monitor configuration through a K8S volume bound to a [Config Map](https://kubernetes.io/es/docs/concepts/configuration/configmap/), replacing the default configuration already present in the container image.

To fine-tune what logs are being monitored, refer to the LogMonitor documentation.

## Environment variable promotion

All the environment variables you setup for a container will be process injected to the Entry Point or the Shell. They are **not** (and should not) be system wide environment variables. That means that these ENV will - by default - not be seen by scheduled tasks, IIS, or any other process that does not spin off the entry point itself. 

If you need some of these environment variables promoted to system so that they can be seen by any other process inside the container (services, IIS, etc.) use the SBS_PROMOTE_ENV_REGEX environment variable

```powershell
SBS_PROMOTE_ENV_REGEX=^SBS_ # Regular expresion to match ENV that you want to promote to system
```

All the environment variables that have a name that matches the Regular Expression in SBS_PROMOTE_ENV_REGEX will be promoted to System Wide environment variables.

Be careful to get your timings and services startup right. If you have an application pool in IIS that is in autostart mode, there is chance that it will be started before the Entry Point script promotes the environment variables. The solution here is that you should design your container to have everything stopped by default, and do a **controlled** bootstrap using Entry Point script extensions (placing your startup logic in entrypoint/init, continue reading for more information about this).

If you have sensible information in your environment variables that you don't want to be seen at the system level, the Entry Point script has automated logic to encrypt using DPAPI any environment variable that you define by prepending "_PROTECT".

In example:

```powershell
MYSENSIBLEPWD_PROTECT="verysafepassword?"
```

This will be renamed in-process to 

```powershell
MYSENSIBLEPWD="ENCODEDPASSWORDWITHDPAPI"
```

Then you can promote that to system level

```powershell
SBS_PROMOTE_ENV_REGEX=^MYSENSIBLEPWD$
```

You can then retrieve it and decode it in your application

```powershell
$password = [System.Environment]::GetEnvironmentVariable("MYSENSIBLEPWD");
$password = [Convert]::FromBase64String($password);
$password = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($password, $null, 'LocalMachine'));

# You can also use the included ps function
$decodedValue = SbsDpapiDecode -EncodedValue $SBS_LOCALADMIN_ENCODED
```

This uses Machine Level DPAPI encryption and it is just designed to avoid leakage of sensible information in environment variables. Let's say you have an APM for IIS that sends all ENV data to the APM, because this sensible information is DPAPI encrypted it will be safe.

This **does not protect the information from being decoded by any other process running inside the container**. That is totally possible.

## Environment hot reload and K8S config maps + secrets

The image will process and add to the environment variables any json files placed in:

```powershell
c:\environment.d\
```

You can also mount any secrets as volumes in:

```powershell
c:\secrets.d\
```

where **the secret filename will be the environment variable name, and the file contents the environment variable value.**

Changes to these files are checked every 8 seconds in the entry point, and **environment variables updated accordingly**. Note that this **does not** mean that whatever this environment variables controls or affects is going to be updated, it depends on each specific setting and how it is used.

Configuring environment through a Json file has some advantages:

* Easily map a K8S config map to your container configuration
* Update the container configuration without needing to re-schedule the K8S pods (K8S will automatically update volume mounted config maps when the config map changes, without rescheduling the pod)

This is an example configmap from a terraform file:

```terraform
resource "kubernetes_config_map" "env_config" {
  metadata {
    name      = "env-config-map"
    namespace = local.k8sappnamespace
  }
  data = {
    "env.json" = jsonencode({
      "MSSQL_LIFECYCLE"                     = "BACKUP",
      "MSSQL_DB_NAME"                       = "mytestdatabase",
      "MSSQL_DB_RECOVERYMODEL"              = "FULL",
      "MSSQL_PATH_BACKUP"                   = "d:\\backup",
      "SBS_ENTRYPOINTERRORACTION"           = "Continue",
      "SBS_TEMPORARY"                       = "d:\\temp",
      "MSSQL_DISABLESHUTDOWNTIMEOUTCHECK"   = "True",
      "SBS_PROMOTE_ENV_REGEX"               = "^SBS_|^MSSQL_",
      "MSSQL_ADMIN_USERNAME"                = "sa",
      "MSSQL_ADMIN_PWD"                     = random_password.sqladmin.result,
      "SBS_GETEVENTLOG"                     = jsonencode([{ LogName : "Application", Source : "*", MinLevel : "Information" }, { LogName : "System", Source : "*", MinLevel : "Warning" }])
      "SBS_CRON_MssqlLog"                   = "{\"Once\":true,\"At\":\"2023-01-01T00:00:00\",\"RepetitionInterval\": \"00:10:00\", \"RepetitionDuration\": \"Timeout.InfiniteTimeSpan\"}",
      "MSSQL_BACKUP_LOGSIZESINCELASTBACKUP" = "200",
      "MSSQL_BACKUP_TIMESINCELASTLOGBACKUP" = "600",
      "SBS_INITASYNC"                       = true
    }),
    "logmonitorconfig.json" = jsonencode({
      "LogConfig" : {
        "sources" : [
          {
            "type" : "File",
            "directory" : "C:\\ProgramData\\New Relic\\newrelic-infra\\",
            "filter" : "*.log",
            "includeSubdirectories" : false
          }
        ]
      }
    })
  }
}
```

When the environment configuration is refreshed, all powershell scripts in the refresh folder will be invoked

```powershell
c:\entrypoint\refreshenv
```

If you want to support hot-reloading of configuration in your application, place your configuration script in refreshenv.

Note that these scripts are **NOT** executed on container initial startup, only after the system detects changes in the configuration values.

## Memory and CPU footprint

Because the entry point to this image is a powershell script, the minimum memory footprint for this image is **about 80Mb** (doing nothing). That is what powershell.exe plus some other windows services will need.

In terms of CPU usage, the actual consumption might vary depending on the type of CPU. On a [Standard_D2S_V3](https://learn.microsoft.com/es-es/azure/virtual-machines/dv3-dsv3-series) which has one of the most basic CPU available on Azure (after the Burstable Series) you get about 5 milli-VCPU.

To avoid the INIT scripts impacting the entry point memory footprint, you can make the initialization logic run asynchronously  with the environment variable SBS_INITASYNC. It can happen that these initialization scripts will load libraries like dbatools that have a noticeable memory footprint: if run synchronously this memory is not freed and will be retained by the entry point.

## OpenSSH

The image comes with the OpenSSH server Windows Feature enabled and configured to use passwords. The service is disabled **by default** and should only be enabled for diagnostics or troubleshooting.

To access your container using SSH:

```powershell
Set-Service -Name ssh-agent -StartupType Manual;
Start-Service -Name ssh-agent;
Set-Service -Name sshd -StartupType Manual;
Start-Service -Name sshd;
net user localadmin @MyP@ssw0rd
```

You can also set environment variables to have this automatically configured when the container starts:

```powershell
- SBS_LOCALADMINPWD_PROTECT=P@ssw0rd
- SBS_ENABLESSH=true
```

## Log rotation

A unix style logrotation utility is installed https://github.com/theohbrothers/Log-Rotate and runs every day at 3AM.

You can place your log rotation custom configurations using a unix like style

```powershell
c:\logrotate\log-rotate.d
```

## Scheduled Tasks

Some of the images might deploy Schedule Tasks. To adjust the triggers of the tasks you can use:

```
- 'SBS_CRON_TaskName={"Daily":true,"At":"2023-01-01T05:00:00","DaysInterval":1}'
```

The available arguments in the JSON definition are passed to: [New-ScheduledTaskTrigger (ScheduledTasks) | Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger?view=windowsserver2022-ps)

Examples of scheduled task configurations:

```json
# Every 15 minutes
"{\"Once\":true,\"At\":\"2023-01-01T00:00:00\",\"RepetitionInterval\": \"00:10:00\", \"RepetitionDuration\": \"Timeout.InfiniteTimeSpan\"}"

# Every saturday at 03:00
'{"Weekly" : true, "At": "2023-01-01T03:00:00", "DaysOfWeek": ["Saturday"], "WeeksInterval": 1}';

# Every day at 04:00
'{"Daily" : true, "At": "2023-01-01T04:00:00", "DaysInterval": 1}'
```

If you need any of the tasks to run immediately on boot, use the *SBS_CRONRUNONBOOT* environment variable to define a comma separated list of scheduled tasks to run on boot.

If you want to make sure you have proper traceability of scheduled task failures, whatever you run in the scheduled task make sure is invoked through the helper script provided in the image:

```xml
<Exec>
   <Command>C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe</Command>
   <Arguments>-File "c:\cron\runscript.ps1" -path "c:\cron\scripts\logrotaterun.ps1"	    </Arguments>
</Exec>
```

This script treats errors and logs calls to the scheduled task on the Application::SbsContainer event source. You can use this to monitor scheduled task behaviours on an external logging system.

## Startup, shutdown and readyness

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

By default the init scripts are run synchronously, if you want to run them asynchronously, use the SBS_INITASYNC environment variable. Running them synchronously is usually much faster, but remember that Powershell will lock assemblies that have been loaded in to the script plus any imported modules during initialization will affect the entry point memory footprint. Using the asynchronous mode will prevent this from happening as the assemblies are released when the initialization job is over.

To check for container readyness the entrypoint script will write a "ready" file to the c:\drive, so you can check in K8S if the container has been successfully through the initilization process:

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

Note that if you are using docker and starting/stopping the same image, the image state is preserved  so this readiness approach will only work reliably for K8S where the container starts always from a pristine state. The teardown process will attempt to delete the ready flag, so it should also work in docker.

For shutdown scripts please consider the following important information: inside a windows container - by default - it is complex and tricky to setup shutdown logic that keeps the image running until you are done: [Unable to react to graceful shutdown of (Windows) container · Issue #25982 · moby/moby (github.com)](https://github.com/moby/moby/issues/25982)

To deal with this, this image overrides the default process shutting down timeout boosting it to 15 seconds versus the default 5 seconds. You can tune this through the SBS_SHUTDOWNTIMEOUT  environment variable.

```powershell
# 60 Seconds shutdown timeout, for containers that need long lasting teardown logic
SBS_SHUTDOWNTIMEOUT=60
```

**Any dangling process** opened by the container manager (i.e. containerd) (such as a remote console in either K8S or docker) will keep your container from being freed during the timeout period (and up to the Shutdown Timeout). To deal with this, we assume that the entry point should be the only source of shutdown blocking, and anything that needs to be shutdown gracefully should be dealt with in the entry point. The entry point will forcefully close these dangling processes if any, this is controlled through the environment variable:

```powershell
SBS_SHUTDOWNCLOSEPROCESSES=cmd,powershell,pwsh,logmonitor
```

If none specified, defaults to "cmd,powershell,pwsh".

### Handling shutdown in Kubernetes

[Container Lifecycle Hooks | Kubernetes](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/)

All the previous setup is to provide a consistent and controlled shutdown experience in docker. In K8S, they have specific ways to deal with shutdown through the pre_stop hook.

If you publish this container image to a K8S environment, you should configure shutdown using a pre_stop hook:

```YAML
# Make sure we tune the termination grace period in K8S
termination_grace_period_seconds = 600

lifecycle {
  pre_stop {
     exec {
       command = ["powershell.exe", "-File", "c:\\entrypoint\\shutdown.ps1"]
     }
   }
}
```

The image is able to detect that the shutdown logic has already been executed, and will not trigger it during entry point shutdown. You can always disable automatic shutdown as part of the entry point through SBS_DISABLEAUTOSHUTDOWN.

### Final thoughts on configuring shutdown

When developing with docker, use a high SBS_SHUTDOWNTIMEOUT to control and debug container shutdowns. But make sure that you are careful with container consoles being open, or your container will get stuck (even with the use of SBS_SHUTDOWNCLOSEPROCESSES, this is not bullet proof and seems no be working always).

In production K8S environments, because we have hooks to deal with this, try to keep SBS_SHUTDOWNTIMEOUT low to avoid stuck container shutdowns (i.e. 15-20s), set SBS_AUTOSHUTDOWN=0 and make sure you have your pre_stop hook and termination_grace_period_seconds properly configured.

## Time Zone

To set the container time zone during startup:

```powershell
SBS_CONTAINERTIMEZONE=Pacific Standard Time
```

## Start and Stop services as part of the container lifecycle

To start services with the container - even if they are disabled at the image level - use:

```yaml
SBS_SRVENSURE=sshd;service2;service3
```

Their startup type will be set to automatic, and they will be started.

If you have services that you want to gracefully stop when the container stops use:

```
SBS_SRVSTOP=was;w3svc;iisadmin;MSSQLSERVER
```

## Powershell Functions

For convenience, if you place a Powershell function inside a script at:

```powershell
c:\ProgramFiles\WindowsPowerShell\Modules\Sbs\Functions\MyExampleFunction.ps1
```

This will be available for your entry point scripts and inside the container. The function needs to be named exactly as the powershell file so that it can be automatically detected.

## Automatic Directory Creation

The container supports automatic directory creation during initialization through the `CREATEDIR_` environment variable pattern. This is useful for ensuring required directories exist before your application starts.

### Usage

Set environment variables that start with `CREATEDIR_` followed by any descriptive name, with the directory path as the value:

```yaml
environment:
  - CREATEDIR_LOGS=C:\App\Logs
  - CREATEDIR_DATA=C:\App\Data
  - CREATEDIR_TEMP=C:\App\Temp
  - CREATEDIR_UPLOADS=C:\inetpub\uploads
```

### Behavior

- **Recursive Creation**: Directories are created recursively (parent directories are created if they don't exist)
- **Safe Operation**: If a directory already exists, it will be skipped without error
- **Early Execution**: Directories are created during the `0005_CreateDirectories.ps1` initialization script
- **Error Handling**: Failed directory creation will be logged but won't stop container startup

### Examples

```bash
# Docker run example
docker run -e CREATEDIR_APPDATA=C:\MyApp\Data -e CREATEDIR_LOGS=C:\MyApp\Logs myimage

# Docker Compose example
environment:
  - CREATEDIR_CACHE=C:\App\Cache
  - CREATEDIR_REPORTS=D:\Reports\Output
```

This feature eliminates the need to manually create directories in your application code or custom scripts.

