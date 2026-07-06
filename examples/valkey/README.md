# Valkey

Valkey is an open source, in-memory data store compatible with the Redis protocol. This example shows how to run Valkey with KubeBlocks.

## Features In KubeBlocks

### Lifecycle Management

| Topology | Horizontal scaling | Vertical scaling | Expand volume | Restart | Stop/Start | Configure | Expose | Switchover |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| standalone | Yes | Yes | Yes | Yes | Yes | Yes | Yes | N/A |
| replication | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |

### Backup and Restore

| Feature | Method | Description |
| --- | --- | --- |
| Full backup | datafile | Runs Valkey physical backup with BGSAVE and uploads the data archive through DataProtection. |
| Volume snapshot | volume-snapshot | Uses CSI snapshots when the environment provides VolumeSnapshot capability. |

### Versions

| Major Version | Supported service versions |
| --- | --- |
| 8.x | 8.0.0, 8.0.1, 8.0.9, 8.1.0, 8.1.3, 8.1.8 |
| 9.x | 9.0.0, 9.0.4, 9.1.0 |

### Cluster (sharding) topology — v1 boundary

`topology: cluster` deploys Valkey Cluster: N shards (each one master plus
replicas) with the 16384 hash slots evenly distributed. See
[cluster-sharding.yaml](cluster-sharding.yaml).

| Boundary | v1 support |
|---|---|
| Valkey version | 9 only |
| Shards | 3..32 |
| Replicas per shard | 1..5 |
| Networking | in-cluster only — clients must be cluster-aware (MOVED/ASK); NodePort/LB direct-to-shard is rejected at render time |
| TLS | not yet supported in cluster mode (rejected at render time) |
| Custom account secret | not yet wired in cluster mode (rejected at render time) |
| Backup | per-shard datafile (BGSAVE snapshot + ACL; nodes.conf is never archived) |
| Restore | same shard count only — always set `RESTORE_TARGET_SHARDS` via restore-env ([restore-sharding.yaml](restore-sharding.yaml)); mismatch is refused before pods start |

## Prerequisites

- Kubernetes cluster with KubeBlocks installed.
- Valkey addon installed.
- Namespace `demo` created:

```bash
kubectl create ns demo
```

## Examples

### Create a replication cluster

```bash
kubectl apply -f examples/valkey/cluster.yaml
kubectl get cluster -n demo valkey-replication
kubectl get pod -n demo -l app.kubernetes.io/instance=valkey-replication -L kubeblocks.io/role
```

The cluster contains one Valkey data component and one Valkey Sentinel component. Replication examples use major-specific topologies such as `replication-9` or `replication-8` so data and Sentinel resolve to the same Valkey major. The data component starts with one primary and two secondaries; Sentinel provides failover and targeted switchover.

To create an 8.x replication cluster:

```bash
kubectl apply -f examples/valkey/cluster-valkey8.yaml
```

### Create a standalone cluster

```bash
kubectl apply -f examples/valkey/cluster-standalone.yaml
```

### Create a TLS cluster

```bash
kubectl apply -f examples/valkey/cluster-tls.yaml
```

### Configure dynamic parameters

```bash
kubectl apply -f examples/valkey/configure.yaml
kubectl describe ops -n demo valkey-reconfiguring
```

### Backup and restore

Create a BackupRepo first, then create a datafile backup:

```bash
kubectl apply -f examples/valkey/backuprepo.yaml
kubectl apply -f examples/valkey/backup.yaml
```

After the backup is completed, update the backup name in `restore.yaml`, then run:

```bash
kubectl apply -f examples/valkey/restore.yaml
```

### Switchover

Automatic candidate selection:

```bash
kubectl apply -f examples/valkey/switchover.yaml
```

Specified candidate:

```bash
kubectl apply -f examples/valkey/switchover-specified-instance.yaml
```

### Day-2 operations

```bash
kubectl apply -f examples/valkey/scale-out.yaml
kubectl apply -f examples/valkey/scale-in.yaml
kubectl apply -f examples/valkey/verticalscale.yaml
kubectl apply -f examples/valkey/volumeexpand.yaml
kubectl apply -f examples/valkey/restart.yaml
kubectl apply -f examples/valkey/stop.yaml
kubectl apply -f examples/valkey/start.yaml
kubectl apply -f examples/valkey/expose-enable.yaml
kubectl apply -f examples/valkey/expose-disable.yaml
```

### Render the cluster chart

```bash
helm template valkey addons-cluster/valkey -n demo
helm template vstandalone addons-cluster/valkey -n demo --set mode=standalone
helm template vtls addons-cluster/valkey -n demo --set tlsEnable=true
```
