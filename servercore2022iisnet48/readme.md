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

