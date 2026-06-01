# Mariadb

MariaDB is a high performance open source relational database management system that is widely used for web and application servers

## Features In KubeBlocks

### Lifecycle Management

Per-topology support matrix. The MariaDB ClusterDefinition currently exposes three user-facing topologies: `standalone`, `replication`, and `galera`. Async vs semi-sync behavior is an install-time replication mode under the `replication` topology, not a separate ClusterDefinition topology. `Yes (verified)` has a recorded end-to-end evidence chain; `Yes (declared)` means the chart wires the action but a full release-standard evidence chain has not yet been recorded; `No` means the topology does not implement the lifecycle action:

| Topology | Horizontal scaling | Vertical scaling | Expand volume | Restart | Stop/Start | Configure | Expose | Switchover |
|---|---|---|---|---|---|---|---|---|
| standalone | No | Yes | Yes | Yes | Yes | No | Yes | No |
| replication (async / semisync install mode) | Yes (declared) | Yes | Yes | Yes | Yes | Yes (declared) | Yes | Yes (verified) |
| galera | Yes (declared) | Yes | Yes | Yes | Yes | Yes (declared) | Yes | No |

Notes:
- `Switchover (verified)` for `replication` covers the OpsRequest path with bounded role transition. Semi-sync mode is selected by `mariadb.replication.mode=semisync` when installing or upgrading the addon; users should still create Clusters with `spec.topology: replication`.
- `Configure (declared)` means the chart wires `ParametersDefinition` and `reconfigure.exec` plus the `replicationMode` synthetic-parameter mapper. Only a subset of parameters has end-to-end runtime evidence today, so per-parameter coverage is "declared" until a parameter is exercised in a recorded test artifact.

### Versions

`ComponentVersion` lists multiple release tags, but only `10.6.15` (standalone) and `11.4.10` (replication async/semi-sync mode / galera) currently have an evidence-supported install + smoke chain. Other tags listed in `cmpv.yaml` are API-compatible but unproven; treat them as "declared but unverified":

| Topology | Verified release | Declared but unproven |
|---|---|---|
| standalone | 10.6.15 | — |
| replication (async / semisync install mode) | 11.4.10 | 11.4.5, 11.4.8, 11.8.4, 12.0.2 |
| galera | 11.4.10 | 11.4.5, 11.4.8 |

### Extended capability declarations (claim-only acceptance)

The following capabilities are **not declared** by the MariaDB chart today. Treat them as "not supported" rather than "untested":

- Backup encryption (passphrase, method formatVersion, snapshot artifact, repository artifact)
- Selective backup / restore, `RestoreKubeResources`, cross-topology / cross-sharding restore, multi-target `sourceBackupTargetName`
- PITR / continuous backup
- Sharding
- Proxy in front of the engine
- Host network / `hostAliases` / `hostPort` / advertised LoadBalancer address
- Cross-namespace `ServiceRef`

The following capability is declared **only for the `standalone` topology** and is not yet wired into multi-instance topologies. Multi-instance + TLS should be treated as "not declared, not supported" until the corresponding `cmpd-replication*.yaml`, `cmpd-semisync.yaml`, or `cmpd-galera.yaml` declares the TLS spec and a topology-aware evidence chain is recorded:

- TLS-only / mutual TLS / certificate mounting at the engine layer

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Zookeeper Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

Create a standalone MariaDB cluster with ONE replica:

```yaml
# cat examples/mariadb/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mariadb-cluster
  namespace: demo
spec:
  clusterDef: mariadb
  topology: standalone
  terminationPolicy: Delete
  componentSpecs:
    - name: mariadb
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      # Specifies a list of PersistentVolumeClaim templates that define the storage
      # requirements for the Component.
      volumeClaimTemplates:
        # Refers to the name of a volumeMount defined in
        # `componentDefinition.spec.runtime.containers[*].volumeMounts
        - name: data
          spec:
            # The name of the StorageClass required by the claim.
            # If not specified, the StorageClass annotated with
            # `storageclass.kubernetes.io/is-default-class=true` will be used by default
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                # Set the storage size as needed
                storage: 20Gi
```

```bash
kubectl apply -f examples/mariadb/cluster.yaml
```

Create a primary/secondary replication Cluster with two replicas:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mariadb-replication
  namespace: demo
spec:
  clusterDef: mariadb
  topology: replication
  terminationPolicy: Delete
  componentSpecs:
    - name: mariadb
      serviceVersion: "11.4.10"
      replicas: 2
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
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

Semi-sync replication uses the same `replication` topology. Select it when installing or upgrading the addon:

```bash
helm upgrade --install mariadb ./addons/mariadb --set replication.mode=semisync
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/mariadb/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mariadb-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mariadb-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: mariadb
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/mariadb/verticalscale.yaml
```

### Expand volume

Increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/mariadb/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mariadb-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mariadb-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: mariadb
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/mariadb/volumeexpand.yaml
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/mariadb/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mariadb-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mariadb-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: mariadb

```

```bash
kubectl apply -f examples/mariadb/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/mariadb/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mariadb-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mariadb-cluster
  type: Stop

```

```bash
kubectl apply -f examples/mariadb/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/mariadb/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mariadb-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mariadb-cluster
  type: Start

```

```bash
kubectl apply -f examples/mariadb/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo mariadb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo mariadb-cluster
```

## Known Issues

### Semi-sync Replication: `rpl_semi_sync_master_wait_no_slave` Should Be Set to `ON`

**Affected versions**: 11.4.5, 11.4.8, 11.4.9, 11.4.10 (all tested versions)

**Upstream bug**: [MDEV-36934](https://jira.mariadb.org/browse/MDEV-36934)

When `rpl_semi_sync_master_wait_no_slave=OFF` (MariaDB default) and the secondary is killed via SIGKILL, the primary enters a permanent deadlock after the secondary reconnects. All new connections to the primary time out indefinitely, requiring a manual restart.

**Root cause**: `commit_trx()` returns early when no slave is connected, leaving a THD entry in the `Active_tranx` list. When the secondary reconnects and sends a TCP RST, `clear_active_tranx_nodes()` signals the dangling THD via `pthread_cond_signal()` while holding `LOCK_binlog`, deadlocking all subsequent commits.

**Recommendation**: Use MariaDB **11.8.4 or later** for semi-sync replication. MDEV-36934 is fixed in 11.8.4 — T5 scenario (kill secondary, write during downtime, rejoin) passes cleanly with `master_status=ON` resuming immediately after rejoin.

Additionally, the KubeBlocks MariaDB addon sets `rpl_semi_sync_master_wait_no_slave=ON` in `config/mariadb-semisync.tpl`. This causes writes to block (up to `rpl_semi_sync_master_timeout`, default 5s) when no semi-sync slave is connected, then fall back to async mode.

If you must use 11.4.x for semi-sync replication, be aware that a secondary SIGKILL will cause the primary to deadlock permanently after the secondary reconnects. Manual restart of the primary is required to recover.
