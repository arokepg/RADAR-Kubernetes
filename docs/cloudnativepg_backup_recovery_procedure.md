# Backup Recovery Procedure for Cloudnative Postgres

By default, backups are performed for all cloudnative pg databases and are performed daily and are stored in MinIO for 7 days.
This should ensure that in the event that the data of a persistent volume of the cloudnativepg database is lost,
the data can be recovered using the backup stored in MinIO. 

### Restore Backups
To restore a backup, you need to add the values below in the `production.yaml` file to the cloudnative pg configuration at the level of `cluster`. 
Note that the `clusterName` value should be the same as the cluster name with `-cluster` appended to the cluster name. 
Additionally, the s3 bucket and path should point to the correct location within MinIO.
If the configuration is correct, the cloudnative pg cluster will be restored from the backup after the helmfiles are applied or synced.
```YAML
cluster:
    mode: recovery
    recovery:
        method: object_store
        clusterName: "clusterName-cluster"
        endpointURL: "http://minio:9000"
        provider: s3
        s3:
            region: ""
            bucket: "minioBucket"
            path: "pathToBucket"
            accessKey: "minioAccessKey"
            secretKey: "minioSecretKey"
```