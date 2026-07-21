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

## Prerequisites

- Kubernetes cluster with KubeBlocks installed.
- Valkey addon installed.
- Namespace `demo` created:

```bash
kubectl create ns demo
```

## Examples

### Create a replication cluster

```yaml
# cat examples/valkey/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: valkey-replication
  namespace: demo
spec:
  terminationPolicy: Delete
  clusterDef: valkey
  topology: replication-9
  componentSpecs:
    - name: valkey-sentinel
      serviceVersion: "9.0.0"
      replicas: 3
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 5Gi
    - name: valkey
      serviceVersion: "9.0.0"
      disableExporter: false
      replicas: 3
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi

```

```bash
kubectl apply -f examples/valkey/cluster.yaml
kubectl get cluster -n demo valkey-replication
kubectl get pod -n demo -l app.kubernetes.io/instance=valkey-replication -L kubeblocks.io/role
```

The cluster contains one Valkey data component and one Valkey Sentinel component. Replication examples use major-specific topologies such as `replication-9` or `replication-8` so data and Sentinel resolve to the same Valkey major. The data component starts with one primary and two secondaries; Sentinel provides failover and targeted switchover.

To create an 8.x replication cluster:

```yaml
# cat examples/valkey/cluster-valkey8.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: valkey-8-replication
  namespace: demo
spec:
  terminationPolicy: Delete
  clusterDef: valkey
  topology: replication-8
  componentSpecs:
    - name: valkey-sentinel
      serviceVersion: "8.1.3"
      replicas: 3
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 5Gi
    - name: valkey
      serviceVersion: "8.1.3"
      disableExporter: false
      replicas: 3
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi

```

```bash
kubectl apply -f examples/valkey/cluster-valkey8.yaml
```

### Create a standalone cluster

```yaml
# cat examples/valkey/cluster-standalone.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: valkey-standalone
  namespace: demo
spec:
  terminationPolicy: Delete
  clusterDef: valkey
  topology: standalone
  componentSpecs:
    - name: valkey
      serviceVersion: "9.0.0"
      disableExporter: false
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi

```

```bash
kubectl apply -f examples/valkey/cluster-standalone.yaml
```

### Create a TLS cluster

```yaml
# cat examples/valkey/cluster-tls.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: valkey-tls
  namespace: demo
spec:
  terminationPolicy: Delete
  clusterDef: valkey
  topology: replication-9
  componentSpecs:
    - name: valkey-sentinel
      serviceVersion: "9.0.0"
      replicas: 3
      tls: true
      issuer:
        name: KubeBlocks
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 5Gi
    - name: valkey
      serviceVersion: "9.0.0"
      disableExporter: false
      replicas: 3
      tls: true
      issuer:
        name: KubeBlocks
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi

```

```bash
kubectl apply -f examples/valkey/cluster-tls.yaml
```

### Configure dynamic parameters

```yaml
# cat examples/valkey/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: valkey-reconfiguring
  namespace: demo
spec:
  clusterName: valkey-replication
  type: Reconfiguring
  force: false
  reconfigures:
    - componentName: valkey
      parameters:
        - key: maxmemory-policy
          value: allkeys-lru
        - key: loglevel
          value: notice
  preConditionDeadlineSeconds: 0

```

```bash
kubectl apply -f examples/valkey/configure.yaml
kubectl describe ops -n demo valkey-reconfiguring
```

### Backup and restore

Create a BackupRepo first, then create a datafile backup:

```yaml
# cat examples/valkey/backuprepo.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupRepo
metadata:
  name: valkey-backuprepo
  annotations:
    dataprotection.kubeblocks.io/is-default-repo: "true"
spec:
  storageProviderRef: oss
  accessMethod: Tool
  config:
    bucket: <your-bucket>
    region: <your-region>
  credential:
    name: <credential-for-backuprepo>
    namespace: kb-system
  pvReclaimPolicy: Retain

```

```bash
kubectl apply -f examples/valkey/backuprepo.yaml
kubectl apply -f examples/valkey/backup.yaml
```

After the backup is completed, update the backup name in `restore.yaml`, then run:

```yaml
# cat examples/valkey/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: valkey-replication-restore
  namespace: demo
spec:
  restore:
    source:
      apiGroup: dataprotection.kubeblocks.io
      kind: Backup
      name: valkey-backup-datafile
      namespace: demo
    parameters:
      dataprotection.kubeblocks.io/source-target-name: valkey
      dataprotection.kubeblocks.io/volume-restore-policy: Parallel
      dataprotection.kubeblocks.io/restore-env: '[{"name":"DATA_REPLICA_COUNT","value":"3"},{"name":"POST_RESTORE_SENTINEL_EXPECTED_COUNT","value":"3"}]'
  terminationPolicy: Delete
  clusterDef: valkey
  topology: replication-9
  componentSpecs:
    - name: valkey-sentinel
      serviceVersion: "9.0.0"
      replicas: 3
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 5Gi
    - name: valkey
      serviceVersion: "9.0.0"
      disableExporter: false
      replicas: 3
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi

```

```bash
kubectl apply -f examples/valkey/restore.yaml
```

### Switchover

Automatic candidate selection:

```yaml
# cat examples/valkey/switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: valkey-switchover
  namespace: demo
spec:
  clusterName: valkey-replication
  type: Switchover
  switchover:
    - componentName: valkey
      instanceName: valkey-replication-valkey-0

```

```bash
kubectl apply -f examples/valkey/switchover.yaml
```

Specified candidate:

```yaml
# cat examples/valkey/switchover-specified-instance.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: valkey-switchover-specified
  namespace: demo
spec:
  clusterName: valkey-replication
  type: Switchover
  switchover:
    - componentName: valkey
      instanceName: valkey-replication-valkey-0
      candidateName: valkey-replication-valkey-1

```

```bash
kubectl apply -f examples/valkey/switchover-specified-instance.yaml
```

### Day-2 operations

```yaml
# cat examples/valkey/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: valkey-scale-out
  namespace: demo
spec:
  clusterName: valkey-replication
  type: HorizontalScaling
  horizontalScaling:
    - componentName: valkey
      scaleOut:
        replicaChanges: 1

```

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
