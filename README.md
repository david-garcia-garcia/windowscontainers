[![CircleCI](https://dl.circleci.com/status-badge/img/circleci/FTP17q9GoCxp3a3xg3Vspr/VGK8Tj7T1QCqXF1jj6EbV5/tree/master.svg?style=svg&circle-token=CCIPRJ_FAcVmNUHi3TkT94TCgUykb_2c6c5b5e60bc6ebaf24fba3bb47e7784bce34a6d)](https://dl.circleci.com/status-badge/redirect/circleci/FTP17q9GoCxp3a3xg3Vspr/VGK8Tj7T1QCqXF1jj6EbV5/tree/master)

# Windows Containers

Several docker images that support hosting Windows based applications in a reliable and production ready way.

Because of MSSQL Server EULA, the images containing the MSSQL binaries cannot be uploaded.

These all are **unofficial**, **unsupported** and **in no way connected to Microsoft**.

## Quick Start

This repository contains multiple images that cannot be pushed to public repositories due to EULA of some of the software used in the build process. You will have to build and push them to a private repository in order to get started (or you can just test them locally)

Some of these images have dependencies between them.

There is a script to build and push all of the images to a private repository in the root, just run the buildall.ps1 script.

Make sure to replace the URL to your private repository in the script, and that you are authenticated to push images:

```powershell
# Rename envsettings.ps1.template to envsettings.ps1 and complete build params
$Env:MSSQLINSTALL_ISO_URL = "https://xx.blob.core.windows.net/software/mssql.iso";
$Env:MSSQLINSTALL_CU_URL = "https://xx.blob.core.windows.net/software/cu.exe";
$Env:MSSQLINSTALL_CUFIX_URL = "https://xx.blob.core.windows.net/software/cufix.7z";
$ENV:REGISTRY_PATH = "myregistry.azurecr.io/core/"
$ENV:IMAGE_VERSION = "1.0.32";

# Build the images
.\buildall.ps1

# Build and push to the registry
.\buildall.ps1 -Push $true

# Build and run tests
.\buildall.ps1 -Test $true
```

## Image List

**Core Windows Server 2022**

Contains the container lifecycle management setup, plus basic tooling such as 7zip and micro.

See details [here](servercore2022/readme.md).

**IIS Internet Information Services Base Image**

Image with the basics for IIS hosting (including CGI and .NET 45/7/8), with support for SSL termination using CCS - Central Certificate Store.

See details [here](servercore2022iis/readme.md).

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

## Debugging the powershell code

To debug the powershell code in the different images, you use the helper method import functions:

```
. .\importfunctions.ps1   
```

Just remember to call this method again every time you change the implementation of any of the helper functions.
