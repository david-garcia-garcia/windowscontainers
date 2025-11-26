# Base image for IIS Setups for hosting ASP.NET applications

Inherits behaviours from these other images:

* [Server Core 2022](../servercore2022/readme.md) 
* [Server Core 2022 IIS](../servercore2022iis/readme.md) 

Adds the New Relic APM, the image has a default configuration in:

```powershell
C:\ProgramData\New Relic\.NET Agent\newrelic.config.template\newrelic.config
```

Template is in it's own directory to deal with this issue: [EmptyDir not being cleaned up after pod terminated with open file handles · Issue #112630 · kubernetes/kubernetes (github.com)](https://github.com/kubernetes/kubernetes/issues/112630)

You can set the license key through environment

```
NEW_RELIC_LICENSE_KEY
```

setting the license key will both configure the license key and enable the agent in the configuration file.

## New Relic Profiler Environment Variables

The New Relic .NET agent installer sets several environment variables at the system (Machine) level that enable the profiler globally:

- `COR_ENABLE_PROFILING` - Enables the .NET Framework profiler
- `COR_PROFILER` - GUID of the .NET Framework profiler
- `CORECLR_NEW_RELIC_HOME` - Path to New Relic agent directory
- `CORECLR_PROFILER` - GUID of the .NET Core profiler

**During image build, these variables are automatically backed up** by renaming them with a `BACKUP_` prefix (e.g., `BACKUP_COR_ENABLE_PROFILING`). This prevents the profiler from being activated globally, ensuring that:

1. The profiler is not enabled for all processes in the container
2. You have explicit control over when and where the profiler is enabled
3. The original values are preserved for reference or manual configuration
4. **You can attach other profilers** (e.g., DataDog, Application Insights) to different processes or services without conflicts

> **Note:** This design allows you to selectively enable different profilers for different services or processes. For example, you could use New Relic for IIS services while using a different APM solution for background worker processes, all within the same container.

### Automatic IIS Service Environment Restore

To automatically restore the IIS service environment variables (W3SVC and WAS) from the backup created during image build, set the following environment variable:

```
IIS_RESTORE_SERVICE_ENV=true
```

or

```
IIS_RESTORE_SERVICE_ENV=1
```

When enabled, the entrypoint script will:
- Restore the backed-up environment variables from `NR_IIS_BACKUP_W3SVC_ENVIRONMENT` and `NR_IIS_BACKUP_WAS_ENVIRONMENT` to the W3SVC and WAS service registry keys
- This ensures the profiler is enabled only for IIS-related processes, not globally
- The variables are set in the service-specific registry location: `HKLM:\SYSTEM\CurrentControlSet\Services\{W3SVC|WAS}\Environment`

This approach follows the pattern recommended by other APM providers (see [DataDog's implementation](https://github.com/DataDog/dd-trace-dotnet/issues/343)) to avoid global profiler activation.

### Manual Configuration in Kubernetes

If you need different behavior or want to configure the profiler for specific application pools, you can explicitly set these environment variables in your Kubernetes deployment:

```yaml
env:
  - name: COR_ENABLE_PROFILING
    value: "1"
  - name: COR_PROFILER
    value: "{71DA0A04-7777-4EC6-9643-7D28B46A8A41}"
  - name: CORECLR_NEW_RELIC_HOME
    value: "C:\ProgramData\New Relic\.NET Agent\"
  - name: CORECLR_PROFILER
    value: "{36032161-FFC0-4B61-B559-F6C5D41BAE5A}"
```

You can also reference the backup values if needed:
- `BACKUP_COR_ENABLE_PROFILING`
- `BACKUP_COR_PROFILER`
- `BACKUP_CORECLR_NEW_RELIC_HOME`
- `BACKUP_CORECLR_PROFILER`

These backup variables contain the original values set by the New Relic installer.

To override the configuration in K8S, use a configmap:

```terraform
# Configmap
resource "kubernetes_config_map" "app_newrelic_customconfig" {
  provider = kubernetes.cluster
  metadata {
    name      = "${var.application_id}-app-newrelic-config"
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  data = {
    "newrelic.config" = local.nri_config_contents
  }
}

# Volume spec
volume {
  name = "newrelic-config"
  config_map {
    name = kubernetes_config_map.app_newrelic_customconfig.metadata[0].name
   }
}

# Volume mount (note that subpath is avoided on purpose)
volume_mount {
  name       = "newrelic-config"
  mount_path = "C:/ProgramData/New Relic/.NET Agent/newrelic.config.template"
}
```

