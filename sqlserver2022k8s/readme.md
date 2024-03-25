# Microsoft SQL Server 2022 base image - For Kubernetes

This image has configurable behavior based on two concepts:

* **Lifecycle**: through env, you will set a Lifecycle type, this will tell the container how to persistent data lifecycle will be managed.
* **Control operations**: through a control file, you can setup one-time startup commands to run on the container.

## Instance Startup Configuration

Use MSSQL_SPCONFIGURE to run SPCONFIGURE on boot, if any of the changes requires a restart, the script will detect it and restart.

```yaml
MSSQL_SPCONFIGURE=max degree of parallelism:1;backup compression default:1
```

## Backup and Maintenance

The image comes with a well known backup solution already installed:

[SQL Server Backup (hallengren.com)](https://ola.hallengren.com/sql-server-backup.html)

You need to configure backups, the image comes with the following scheduled tasks:

- **MssqlDifferential**: run differential backup on all user databases. Differential is promoted to FULL according to MSSQL_BACKUP_MODIFICATIONLEVEL and MSSQL_BACKUP_CHANGEBACKUPTYPE.
- **MssqlFull**: run full backup on all user databases.
- **MssqlLog**: run log backup on all user databases.
- **MssqlSystem**: run full backups on all system databases

You can schedule these tasks using environment variables:

```yaml
# Full every saturdaY
- 'SBS_CRON_MssqlFull={"Weekly":true,"At":"2023-01-01T02:00:00", "RandomDelay": "00:30:00", "DaysOfWeek": ["Saturday"]}'

# Differential every day at 4:00
- 'SBS_CRON_MssqlDifferential={"Daily":true,"At":"2023-01-01T04:00:00","DaysInterval":1}'

# Log backup every 15 minutes
- 'SBS_CRON_MssqlLog={"Once":true,"At":"2023-01-01T00:00:00","RepetitionInterval": "00:15:00", "RepetitionDuration": "Timeout.InfiniteTimeSpan"}'

# System databases daily at 22:00
- 'SBS_CRON_MssqlSystem={"Daily":true,"At":"2023-01-01T22:00:00","DaysInterval":1}'
```

You can define backup cleanup times for each type of backup (retention)

```yaml
- MSSQL_BACKUP_CLEANUPTIME_LOG=48
- MSSQL_BACKUP_CLEANUPTIME_DIFF=72
- MSSQL_BACKUP_CLEANUPTIME_FULL=128
```

## Master key

A master key with a random password is automatically deployed on start. If this is a persistent setup and a master key already exists, none will be deployed.

## Monitoring Backup and Restores

There is nothing more frustrating when automating database lifecycles than having zero visibility on the state of restores and backups.

To deal with that, a background job is deployed on startup that logs to the Event Viewer every 8 seconds the current state of any backup or restore operation, including information about completed percentage.

![image-20240312091447783](readme_assets/image-20240312091447783.png)

## Monitoring 

### Setup

Monitoring configuration is setup and periodically refreshed through a scheduled task "DeployMssqlNri".

This task:

* Deploys the backup summary table and populating job using SbsDeployDbBackupInfo

* Setups the newrelic identity in the SQL engine using SbsAddNriMonitor
* Configure the newrelic authentication (mssql-config.yml)

To run this immediately after booting use the env configuration:

```yaml
SBS_CRONRUNONBOOT=DeployMssqlNri
```

### Backup State for databases

The image has a Job "RefreshSbsDatabaseBackupInfo" and a table in Master "SbsDatabaseBackupInfo". This job populates the table with summarized backup information for all databases in the SQL engine that you can use to monitor database backup status.

![image-20240312090653947](readme_assets/image-20240312090653947.png)

The new relic MSSQL integration in the image is already configured to push this information to New Relic (see mssql-custom-query.yml) so you can build integrated monitoring panels for MSSQL in New Relic

![image-20240312091029724](readme_assets/image-20240312091029724.png)

Special mention to the backupByDb_modified column, that shows the amount of pages modified since last full backup. This is important if you are using differential to full promotion during backups according to % percentage.

You can now use this information to create a faceted new relic alert that warns you when backups are not working, i.e.

```sql
SELECT max(backupByDb_sinceFull) as 'H since Full' FROM MssqlCustomQuerySample where backupByDb_sinceFull is not null FACET db_Database as Database
```

## SQL Server Agent

The SQL Server Agent is installed and configured, but **disabled** by default.

To enable the agent add the service name to the list of start on boot services in ENV:

```yaml
SBS_SRVENSURE=SQLSERVERAGENT
```

## Full Text Search

Full text search services are installed and enabled in the image.

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
      - MSSQL_ADMIN_PWD_PROTECT=sapwd
      - MSSQL_LIFECYCLE=PERSISTENT
      - MSSQL_PATH_DATA=d:\data
      - MSSQL_PATH_LOG=d:\log
      - MSSQL_PATH_BACKUP=d:\backup
      - MSSQL_PATH_CONTROL=d:\control
      - MSSQL_PATH_SYSTEM=d:\system
      - SBS_TEMPORARY=d:\temp
```

All SQL  paths (MSSQL_PATH_*) have been moved to persistent volume store. This ensures that master, model and everything you setup in this MSSQL instance is retained and stored in persistent storage. The pod can move between nodes in K8S and will recover it's previous state with a minimum downtime. For a zero downtime pod we need to rely on replication/mirroring (pending).

## Memory usage and footpring

The base memory consumption AKA memory footprint for this image is approx. **356Mb**. ~100MB are for the entrypoint and windows services, the other 256MB are for MSSQL Server itself. You cannot run MSSQL with less than 256MB (although official documentation states a minimum of Max Server memory of 128MB). If you push this limit too much, you will loose access to the server and CPU usage will spike - plus your logs will be getting flooded. I have tested 256MB to be the bare minimum to keep MSSQL running (probably due to the image having Full Text Search and SQL Server Agent).

[SQL SERVER - Error: 17300 - The Error is Printed in Terse Mode Because There was Error During Formatting - SQL Authority with Pinal Dave](https://blog.sqlauthority.com/2018/08/16/sql-server-error-17300-the-error-is-printed-in-terse-mode-because-there-was-error-during-formatting/)

MSSQL will use as much memory as possible. This is a huge problem if not controlled in a K8S cluster. The same if you have multiple instances of MSSQL on the same server, they will compete for memory resources.

This can even become more problematic if K8S decides to memory evict your pods. This requires careful planning on how you are going to assign memory to the MSSQL pods.

Currently, memory eviction does not work in windows nodes:

[Windows Nodes Don't Currently Support Out of Memory Eviction (OOMKILL) · Issue #2820 · Azure/AKS (github.com)](https://github.com/Azure/AKS/issues/2820)

Consider configuring the memory release scheduled task. Make sure you run this at a time where it will not be impacting backups or database load. This task temporarily reduces the server configured Max Memory (for a few seconds), forcing a release.

```
'SBS_CRON_MssqlReleaseMemory={"Daily":true,"At":"2023-01-01T05:00:00","DaysInterval":1}'
```

You can also tune the Max Server Memory for the instance through MSSQL_SPCONFIGURE

```yaml
MSSQL_MAXMEMORY=512
```

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

**Backup restore**

| VM Type                                    | Mounted Storage Type                    | Backup Size (GB) | DB Size (GB) | Download                                 | Restore         |
| ------------------------------------------ | --------------------------------------- | ---------------- | ------------ | ---------------------------------------- | --------------- |
| Standard_DS2_v2 (96Mib/s)                  | Azure Premium Files (100Gib - 110Mib/s) | 11.27            | 70           | 50min                                    | 24min (48Mb/s)  |
| Standard_D4s_v3 (96Mib/s with 30min burst) | Azure Premium Files (100Gib - 110Mib/s) | 11.27            | 70           | 50min                                    | 21min (55Mb/s)  |
| Standard_D4s_v3 (96Mib/s with 30min burst) | Azure Disk P10 (100Mib/s)               | 11.27            | 70           | x                                        | 16min (73Mb/s)  |
| Standard_D2s_v3 (48Mib/s)                  | Azure Disk P10 (100Mib/s)               | 11.27            | 70           | Restore directly from Blob               | 24min (48Mb/s)  |
| Standard_L8s_v2                            | x                                       | 11.27            | 70           | Restore directly from Blob on NVME drive | 4min (291 Mb/s) |

**Backup generate**

| VM Type                                    | Mounted Storage Type      | Backup Size (GB) | DB Size (GB) | Backup to mapped storage | Backup To URL |
| ------------------------------------------ | ------------------------- | ---------------- | ------------ | ------------------------ | ------------- |
| Standard_D2s_v3 (48Mib/s)                  | Azure Disk P10 (100Mib/s) | 11.27            | 70           | 16 min                   | 14min         |
| Standard_D4s_v3 (96Mib/s with 30min burst) | Azure Disk P10 (100Mib/s) | 11.27            | 70           | 11 min                   | 10min         |

Speed test in container

```powershell
      Server: KEYYO - Paris (id: 27961)
         ISP: Microsoft Azure
Idle Latency:     1.92 ms   (jitter: 0.05ms, low: 1.85ms, high: 1.95ms)
    Download:  3261.05 Mbps (data used: 5.7 GB)
                  3.48 ms   (jitter: 1.38ms, low: 1.98ms, high: 12.42ms)
      Upload:  1592.78 Mbps (data used: 1.4 GB)
                 39.19 ms   (jitter: 21.54ms, low: 1.29ms, high: 63.08ms)
 Packet Loss:     0.0%
```

