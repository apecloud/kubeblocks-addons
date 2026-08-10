# HugeGraph

This addon runs Apache HugeGraph 1.7.0 as a single HugeGraph Server backed by
RocksDB.

## Capabilities

| Capability | Standalone |
| --- | --- |
| Replicas | Exactly 1 |
| Persistent data | Yes |
| Restart | Yes |
| Stop/Start | Yes |
| Vertical scaling | Yes |
| Volume expansion | Yes, when the StorageClass supports expansion |
| Expose | Yes |
| Full backup/restore | RocksDB checkpoint |
| Horizontal scaling | No |
| Reconfigure | No |
| TLS | No |

The `checkpoint` backup method calls HugeGraph's `snapshot_create` API for
every persistent graph. It uploads graph configurations, a format-versioned
manifest, SHA-256 checksums, and all RocksDB checkpoints through datasafed. It
does not use CSI volume snapshots.

Restore is supported only to a new HugeGraph 1.7.0 standalone Cluster. It
restores the complete instance. Single-graph restore, PITR, incremental backup,
RebuildInstance, cross-version restore, and cross-topology restore are not
supported. The restore action validates every graph config and checkpoint file,
then creates the persistent upstream initialization marker before the first
HugeGraph process starts.

## Storage

The `data` PVC is mounted at `/hugegraph-data`. The addon keeps graph
configuration files, RocksDB directories, WAL directories, and the upstream
initialization marker on this volume. It does not mount a PVC over
`/hugegraph-server`.

On every Pod start, the addon rebuilds HugeGraph's authentication settings in
the replacement container before invoking the upstream entrypoint. A `preStop`
hook runs HugeGraph's shutdown script within a 30-second termination window so
Stop, Restart, and pod replacement close RocksDB cleanly. The hook records its
start and completion in `/hugegraph-data/.kb-prestop.log` for diagnosis.

For additional graphs, use the HugeGraph clone API so the RocksDB provider
creates unique persistent paths:

```bash
curl --fail --user 'admin:<password>' \
  --request POST \
  'http://<host>:8080/graphspaces/DEFAULT/graphs/analytics?clone_graph_name=hugegraph' \
  --header 'Content-Type: application/json' \
  --data '{}'
```

When creating a graph without `clone_graph_name`, explicitly set unique
`rocksdb.data_path` and `rocksdb.wal_path` values that are direct children of
`/hugegraph-data`. Backup fails rather than silently omitting a graph whose
data is outside the managed PVC.

Each graph checkpoint is internally consistent. Checkpoints are created one
graph at a time, so this method does not provide a single cross-graph
transaction timestamp.

## Image

The runtime and data protection actions use
`docker.io/hugegraph/hugegraph:1.7.0`. No custom tools image is required.

## Examples

See `examples/hugegraph` for Cluster, backup, restore, restart, stop/start,
vertical scaling, and volume expansion manifests.
