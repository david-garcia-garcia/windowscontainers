# Microsoft SQL Server 2022 base image - For Kubernetes

This image has configurable behaviour based on two concepts:

* **Lifecycle**: through env, you will set a Lifecycle type, this will tell the container how to persistent data lifecycle will be managed.
* **Control operations**: through a control file, you can setup one-time startup commands to run on the container.

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
