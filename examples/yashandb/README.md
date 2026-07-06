# Yashandb

YashanDB is a new database system completely independently designed and developed by SICS. Based on classical database theories, it incorporates original Bounded Evaluation theory, Approximation theory, Parallel Scalability theory and Cross-Modal Fusion Computation theory, supports multiple deployment methods such as stand-alone/primary-standby, shared cluster, and distributed ones, covers OLTP/HTAP/OLAP transactions and analyzes mixed load scenarios, and is fully compatible with privatization and cloud infrastructure, providing clients with one-stop enterprise-level converged data management solutions to meet the needs of key industries such as finance, government, telecommunications and energy for high performance, concurrency and security.

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- YashanDB Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

> [!NOTE]
> These examples are template-level examples in this PR. Run them only after the target environment has a reachable KubeBlocks control plane, a writable StorageClass, a configured BackupRepository for backup/restore examples, mirrored YashanDB images, and a plan to collect cluster and database evidence. Local Helm rendering can catch template errors, but it does not prove Kubernetes apply, controller reconciliation, database SQL behavior, backup/restore, writer endpoint movement, metrics scraping, or HA recovery.

For local template checks from the repository root, run:

```bash
helm dependency build addons/yashandb
helm template yashandb addons/yashandb -n demo
```

## Examples

### [Create](cluster.yaml)

Create a YashanDB cluster of version `23.4.1.109` with ONE replica.

> [!NOTE]
> This example uses the default addon image version. For enterprise image tags, please contact the vendor and keep `ComponentVersion.serviceVersion` aligned with the actual image version.

```bash
kubectl apply -f examples/yashandb/cluster.yaml
```

To login to the YashanDB console, you can

1. login to the pod:

```bash
kubectl exec -it yashandb-cluster-yashan-0 -- /bin/bash
```

2. login to the YashanDB console:

```sql
yasql sys/yasdb_123
```

To verify whether the database has been initialized successfully, check instance and database status:

- check instance status:

```sql
SQL> select status from v$instance;

STATUS
-------------
OPEN
```

- check database status:

```sql
SQL> select status from v$database;

STATUS
---------------------------------
NORMAL
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/yashandb/verticalscale.yaml
```

### [Horizontal scaling](scale-out.yaml)

> [!NOTE]
> These files show the standard KubeBlocks OpsRequest shape. The current personal image is documented as standalone, so multi-replica behavior still needs real-cluster validation.

Scale out by one replica:

```bash
kubectl apply -f examples/yashandb/scale-out.yaml
```

Scale in by one replica:

```bash
kubectl apply -f examples/yashandb/scale-in.yaml
```

### Fixed-address HA examples

> [!WARNING]
> `cluster-fixed-ha-2.yaml` and `cluster-fixed-ha-3.yaml` are fixed-address HA examples. They require the addon to be installed with `ha.fixedAddress.enabled=true`, a HA-capable YashanDB/yasboot image, stable worker addresses, non-conflicting hostNetwork ports, and YashanDB/yasboot metadata built from those stable addresses. They do not claim ordinary Pod-IP multi-replica HA.

The examples use KubeBlocks per-instance templates to declare one primary plus one or two standby nodes. Before applying them, replace the documentation-only values:

- `192.0.2.10`, `192.0.2.11`, `192.0.2.12` with the worker node addresses that will appear in yasboot metadata;
- `worker-a`, `worker-b`, `worker-c` with the actual `kubernetes.io/hostname` labels;
- `YASDB_HA_CLUSTER_NAME` and ports if the environment uses different names or hostNetwork ports.

> [!WARNING]
> These examples rely on the addon `ComponentVersion` image resolution and must not set `instances[].image`; KubeBlocks 1.0.2 rejects that field. Do not promote this as complete native HA lifecycle until the empty-PVC bootstrap path is validated against the current PR head in the target environment.

Create the SSH Secret required by the empty-PVC yasboot bootstrap. The examples reference this Secret by name and do not store key material in Git:

```bash
ssh-keygen -t rsa -b 4096 -N '' -f ./yashandb-fixed-ha-id_rsa

kubectl -n demo create secret generic yashandb-fixed-ha-ssh \
  --from-file=id_rsa=./yashandb-fixed-ha-id_rsa \
  --from-file=authorized_key=./yashandb-fixed-ha-id_rsa.pub
```

The fixed-address HA image must include YashanDB, yasboot, and SSH utilities. Treat this as an image contract; this PR does not attach current-head runtime evidence for a specific official image source.

Create a fixed-address one-primary-one-standby shape:

```bash
kubectl apply -f examples/yashandb/cluster-fixed-ha-2.yaml
```

Create a fixed-address one-primary-two-standby shape:

```bash
kubectl apply -f examples/yashandb/cluster-fixed-ha-3.yaml
```

Read the limitation contract before using these examples:

```bash
cat examples/yashandb/fixed-ha-limitations.md
```

Enable the optional writer Endpoint reconciler when the fixed-address topology has been built and `yasboot cluster status` reports exactly one `open/normal/primary`:

```bash
kubectl -n demo create secret generic yashandb-writer-reconciler-auth \
  --from-literal=password='<db-password>'
```

```bash
helm upgrade --install yashandb addons/yashandb \
  -n demo \
  -f addons/yashandb/examples/fixed-ha-writer-reconciler-values.yaml
```

Before using the file, replace `clusterName`, `sqlPort`, `endpointPodMap`, and `ha.writerReconciler.image.*` with the target environment values. The example references the database password by Secret name and must not be changed to store a literal password in Git.

Check the writer entry after deployment:

```bash
kubectl -n demo get deploy yashandb-writer-endpoint-reconciler
kubectl -n demo get svc,endpoints yashandb-writer -o wide
kubectl -n demo logs deploy/yashandb-writer-endpoint-reconciler --tail=50
```

The reconciler follows the current primary. Optional automatic `yasboot node failover` is available only when explicitly enabled in the addon values, and ordinary Pod-IP HA remains unsupported.

### [Volume expansion](volumeexpand.yaml)

Expand the `data` volume claim template:

```bash
kubectl apply -f examples/yashandb/volumeexpand.yaml
```

### [Expose](expose-enable.yaml)

Expose the standalone YashanDB service:

```bash
kubectl apply -f examples/yashandb/expose-enable.yaml
```

Disable the exposed service:

```bash
kubectl apply -f examples/yashandb/expose-disable.yaml
```

### [Switchover](switchover.yaml)

> [!NOTE]
> YashanDB switchover is wired as a standby-side operation. Replace `instanceName` with a pod whose roleProbe result is `secondary`.

```bash
kubectl apply -f examples/yashandb/switchover.yaml
```

### [Full backup](backup.yaml)

> [!NOTE]
> This example triggers a full backup through KubeBlocks dataprotection wiring. It still needs current-head KubeBlocks/YashanDB runtime validation before promotion.

```bash
kubectl apply -f examples/yashandb/backup.yaml
```

### [Restore](restore.yaml)

> [!WARNING]
> This restore example covers new-cluster restore from a full backup through `Cluster.spec.restore.source`. It prepares backup data through KubeBlocks, then lets `initDB.sh` run YashanDB NOMOUNT restore during first startup. PITR, incremental restore, in-place restore, and HA restore are not implemented. Validate post-restore `OPEN` status, row counts, and checksums in the target cluster before promoting this example beyond experimental validation.

```bash
kubectl apply -f examples/yashandb/restore.yaml
```

### [PodMonitor](pod-monitor.yaml)

> [!WARNING]
> This example works only after the addon is installed with `metrics.enabled=true`, `metrics.auth.passwordSecretName` pointing to a Secret that contains the exporter-compatible encrypted database password, and an exporter image built or mirrored from `ycm/packages/yashandb_exporter-v0.1.1-159-g906774c-linux-arm64.tar.gz` in the YCM 23.5.13.3 aarch64 package. The exporter sidecar exposes `/metrics` on port `9100` by default.

```bash
kubectl apply -f examples/yashandb/pod-monitor.yaml
```

### [Configure](configure.yaml)

> [!WARNING]
> Stage 5A treats all covered YashanDB parameters as static and restart-required. It does not implement dynamic `ALTER SYSTEM` reload.

```bash
kubectl apply -f examples/yashandb/configure.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/yashandb/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/yashandb/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/yashandb/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo yashandb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo yashandb-cluster
```
