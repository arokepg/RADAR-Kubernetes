# Backup and Recovery Procedure for CloudnativePG Postgresql

## Procedure for making backups

By default, backups are performed for all CloudnativePG Postgresql databases and are performed daily and are stored in
MinIO object storage for 7 days. This ensures that in the event that the data on the persistent volume of the
CloudnativePG database is lost, the data can be recovered using the backup stored in MinIO. Changed in, for instance,
the name of the bucket where backups are stored, the backup frequency or the retention duration can be made in the
following sections in the `production.yaml` file.

### Postgresql

```yaml
cloudnative_postgresql:
  ...
  cluster:
    backups:
      enabled: true
      endpointURL: http://my-other-object-store:9000
      provider: s3
      s3:
        region: eu-west-1
        bucket: "my-fancy-bucket-name"
        path: "/path-inside-bucket"
      scheduledBackups:
        - name: weekly-backup
          schedule: "0 0 0 * * 0"
      retentionPolicy: "100d"
```

### TimescaleDB

Changes to TimescaleDB backups are applied in the `production.yaml` sections of the respective JDBC-connector service.
For instance for the Grafana database, one can set:

```yaml
radar_jdbc_connector_grafana:
  ...
  timescaledb:
    cluster:
      backups:
        enabled: true
        endpointURL: http://my-other-object-store:9000
        provider: s3
        s3:
          region: eu-west-1
          bucket: "my-fancy-bucket-name"
          path: "/path-inside-bucket"
        scheduledBackups:
          - name: weekly-backup
            schedule: "0 0 0 * * 0"
        retentionPolicy: "100d"
```

## Procedure for restoring backups

To restore a backup, you need to add a `recovery:` section to the `cluster:` section of the respective database service
in the `production.yaml` file like so:

### Postgresql

```yaml
cloudnative_postgresql:
  ...
  cluster:
    mode: recovery
    recovery:
      method: object_store
```

### TimescaleDB

For instance for the Grafana database, one can set:

```yaml
radar_jdbc_connector_grafana:
  ...
  timescaledb:
    cluster:
      mode: recovery
      recovery:
        method: object_store
```
