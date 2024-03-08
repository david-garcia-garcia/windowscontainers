# Microsoft SQL Server 2022 base image - For Kubernetes

This image has configurable behavior based on two concepts:

* **Lifecycle**: through env, you will set a Lifecycle type, this will tell the container how to persistent data lifecycle will be managed.
* **Control operations**: through a control file, you can setup one-time startup commands to run on the container.

## Instance Startup Configuration

Use MSSQL_SPCONFIGURE to run SPCONFIGURE on boot, if any of the changes requires a restart, the script will detect it and restart.

```yaml
MSSQL_SPCONFIGURE=max degree of parallelism:1;backup compression default:1
```

## Master key

A master key with a random password is automatically deployed on start. If this is a persistent setup and a master key already exists, none will be deployed.

## Monitoring Backup and Restores

There is nothing more frustrating when automating database lifecycles than having zero visibility on the state of restores and backups.

To deal with that, a background job is deployed on startup that logs to the Event Viewer (LogName=Application and Source=MSSQL_MANAGEMENT) every 8 seconds the current state of any backup or restore operation, including information about completed percentage.

## Lifecycle

The lifecycle determines "how" the image intends to treat persistent data and configuration. I.E. you might totally want to have a configuration-free MSSQL setup where the only persistent thing are the data files themselves. On the other hand, you might want to have total control on the SQL Instance and have any config change you make to it persisted.

### **Persistent**

This is the most simple lifecycle possible, it mostly leaves the base image behavior untouched.

Focusing on the minimum ENV setup needed for this:

```yaml
    volumes:
      - "f:/databases/example/data:d:"
    networks:
      - container_default
    environment:
      - MSSQL_ADMIN_USERNAME=sa
      - MSSQL_ADMIN_PWD=sapwd
      - MSSQL_LIFECYCLE=PERSISTENT
      - MSSQL_PATH_DATA=d:\data
      - MSSQL_PATH_LOG=d:\log
      - MSSQL_PATH_BACKUP=d:\backup
      - MSSQL_PATH_CONTROL=d:\control
      - MSSQL_PATH_SYSTEM=d:\system
      - SBS_TEMPORARY=d:\temp
```

All SQL  paths (MSSQL_PATH_*) have been moved to persistent volume store. This ensures that master, model and everything you setup in this MSSQL instance is retained and stored in persistent storage. The pod can move between nodes in K8S and will recover it's previous state with a minimum downtime. For a zero downtime pod we need to rely on replication/mirroring (pending).

## Control Operations

You can place a "startup.yaml" file in the SSQL_PATH_CONTROL path, the contents of this path will be processed once on container startup, and once done, the file renamed for archiving so it will not be processed again.

In this yaml you can have one or more operations, that will execute sequentially on boot.

**Perform a full restore**

```yaml
steps:
  - type: 'restore_full'
    url: 'https://urltomyfullbackup.bak'
    name: 'MyDatabase' # leavy empty to use ENV MSSQL_DATABASE
    cert: 'https://urltocertificatezipprotectingbackup.zip'
```

If the restore is huge, you can the the progress from the container output or the event viewer.

**Restore from bacpack**

```yaml
steps:
  - type: 'restore_bacpac'
    url: 'https://urltomyfullbackup.bacpac'
    name: 'MyDatabase' # leavy empty to use ENV MSSQL_DATABASE
```

## Benchmarks

Some benchmarks on Azure for database restore from backup (backup stored in Azure Blob)

| VM Type         | Storage Type                            | Backup Size (GB) | DB Size (GB) | Download | Restore | Comments                      |
| --------------- | --------------------------------------- | ---------------- | ------------ | -------- | ------- | ----------------------------- |
| Standard_DS2_v2 | Azure Premium Files (100Gib - 110Mib/s) | 11.27            | 70           | 50min    | 24min   | Expected download time ~2min, |
|                 |                                         |                  |              |          |         |                               |
|                 |                                         |                  |              |          |         |                               |

