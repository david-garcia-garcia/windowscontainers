# Windows Containers

Several docker images that support hosting Windows based applications in a reliable and production ready way.

Because of MSSQL Server EULA, the images containing the MSSQL binaries cannot be uploaded.

These all are **unofficial**, **unsupported** and **in no way connected to Microsoft**.

## Quick Start

This repository contains multiple images that cannot be pushed to public repositories due to EULA of some of the software used in the build process. You will have to build and push them to a private repository in order to get started.

Some of these images have dependencies between them.

There is a script to build and push all of the images to a private repository in the root, just run the buildall.ps1 script.

Make sure to replace the URL to your private repository in the script, and that you are authenticated to push images:

```powershell

# Set the image names in ENV using the imagenames script
.\imagenames.ps1 "myregistry.azurecr.io/core/"

# Example usage with pushing the images (must end in slash)
.\buildall.ps1 -push $true
```

## Image List

**Core base image**

Contains the container lifecycle management setup, plus basic tooling such as 7zip and micro.

See details [here](servercore2022/readme.md).

**SQL Server 2022 With Full Text Search**

Base image with SQL Server and Full Text Search feature.

See details [here](sqlserver2022base/readme.md).

**SQL Server 2022 With Full Text Search - For Kubernetes**

Base image with SQL Server and Full Text Search feature, with configurable behaviour aimed at AKS/K8S deployments.

See details [here](sqlserver2022k8s/readme.md).

Scripting in this image proposes several database lifecycle and backup automation, for seamless integration and production ready deployments on AKS or K8S.

**SQL Server 2022 Analysis Services**

SQL Server 2022 Analysis Services exposed through HTTP.

See details [here](sqlserver2022as/readme.md).
