# HugeGraph Examples

These examples target KubeBlocks `release-1.0` and HugeGraph 1.7.0.
`cluster.yaml` is standalone. `cluster-distributed.yaml` is PD + Store + Server.

## Create

Apply `cluster.yaml`. The Cluster exposes HTTP on port 8080 and Gremlin on
port 8182. The KubeBlocks system account is `admin`.

## Backup

Configure a working BackupRepo, then apply `backup.yaml`. The generated backup
policy name is `hugegraph-cluster-server-backup-policy` and the method is
`checkpoint`.

The backup covers all graph configurations in `/hugegraph-data/graphs` and all
RocksDB checkpoint directories. It does not use a VolumeSnapshotClass.

## Restore

Wait until `hugegraph-cluster-backup` is `Completed`, then apply `restore.yaml`.
The target must be a new one-replica HugeGraph 1.7.0 standalone Cluster with a
`data` volume at least as large as the source.

After restore, verify the target Cluster is Running, authenticate with its
`admin` Secret, list every expected graph, read the source data, and perform a
new write. Backup completion alone does not prove restore.

## Day-2

- `restart.yaml`: restart the server component.
- `stop.yaml` and `start.yaml`: stop and start the server component.
- `verticalscale.yaml`: change CPU and memory.
- `volumeexpand.yaml`: expand the `data` PVC when supported by the StorageClass.

Horizontal scaling, reconfigure, TLS, switchover, PITR, incremental backup,
single-graph restore, and RebuildInstance are not supported in this version.
