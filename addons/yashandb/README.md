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
> This PR provides addon templates, scripts, and examples. The attached validation boundary is local Helm rendering and script syntax checks only. Before promoting backup, restore, fixed-address HA, writer endpoint reconciliation, configure, or monitoring beyond template-level validation, run current-head real-cluster validation with a reachable KubeBlocks control plane, a writable StorageClass, a configured BackupRepository, mirrored YashanDB images, and target-cluster evidence collection. Local Helm rendering does not replace Kubernetes apply, controller reconciliation, database SQL checks, endpoint traffic checks, exporter scrapes, or recovery testing.

For local template checks from the repository root, run:

```bash
helm dependency build addons/yashandb
helm template yashandb addons/yashandb -n demo
```

## Features In KubeBlocks

### Lifecycle Management

| Topology | Horizontal scaling | Vertical scaling | Expand volume | Restart | Stop/Start | Configure | Expose | Switchover |
|---|---|---|---|---|---|---|---|---|
| standalone | Example only | Yes | Example only | Yes | Yes | Static parameters only | Example only | Local wiring |
| fixed-address HA | Per-instance topology example | Not claimed | Not claimed | Proof required | Proof required | Static fallback only | Optional writer reconciler | Proof required |

> [!NOTE]
> Horizontal scaling examples use standard KubeBlocks request shapes and do not claim generic Pod-IP HA. YashanDB fixed-address HA is a separate explicit mode that requires `ha.fixedAddress.enabled=true`, a HA-capable YashanDB/yasboot image, stable worker addresses, non-conflicting hostNetwork ports, and YashanDB/yasboot metadata built from those stable addresses. The fixed-address examples use KubeBlocks per-instance templates to declare one primary plus one or two standby nodes. YashanDB switchover is wired as a standby-side operation: the `Switchover` OpsRequest `instanceName` should target a pod whose role is `secondary`.

The optional writer Endpoint reconciler is enabled with `ha.writerReconciler.enabled=true`. It reconciles a writer Service/Endpoints pair to the current `open/normal/primary` node in fixed-address HA mode. By default it only follows the current primary. Optional automatic database failover is gated by `ha.writerReconciler.failover.enabled=true`. It does not repair generic Pod-IP metadata drift and requires an image that provides `kubectl`. Store the database password in a Kubernetes Secret and set `ha.writerReconciler.dbPasswordSecretName` plus `ha.writerReconciler.dbPasswordSecretKey`.

#### Fixed-address HA bootstrap contract

Fixed-address HA is an opt-in route for environments where YashanDB/yasboot metadata can bind to stable node addresses. It is not ordinary Pod-IP HA.

Before applying `cluster-fixed-ha-2.yaml` or `cluster-fixed-ha-3.yaml`, prepare a Secret for the yasboot SSH identity. Do not commit the generated private key or literal key contents:

```bash
ssh-keygen -t rsa -b 4096 -N '' -f ./yashandb-fixed-ha-id_rsa

kubectl -n demo create secret generic yashandb-fixed-ha-ssh \
  --from-file=id_rsa=./yashandb-fixed-ha-id_rsa \
  --from-file=authorized_key=./yashandb-fixed-ha-id_rsa.pub
```

The fixed-address examples reference this Secret through:

- `YASHANDB_SSH_PRIVATE_KEY` on the initial primary bootstrap node;
- `YASHANDB_AUTHORIZED_KEY` on every fixed-address node.

Use a yasboot-safe logical cluster name in `YASDB_HA_CLUSTER_NAME`, for example `kbfh2` or `kbfh3`. This value is passed to `yasboot` and must not be copied blindly from a Kubernetes `Cluster` name that contains hyphens.

The HA database image must be a yasboot-capable image. Treat the image as a runtime contract instead of relying on a lab image tag. A production image for this route must provide:

- the YashanDB 23.4.1.109 aarch64 package or an equivalent supported runtime package;
- the yasboot package under `/opt/yasboot-package` with runnable `bin/yasboot`;
- OpenSSH server/client utilities usable by the `yashan` user;
- a writable `/home/yashan/mydb` data mount;
- compatibility with `fixed-ha-bootstrap.sh`, `check_alive.sh`, and `check_role.sh`.

`yashandb-1.2.0-alpha.0` is the current immutable `ComponentDefinition` revision for this template path. Earlier alpha revisions are development history only. This PR does not attach current-head runtime evidence for fixed-address HA, writer endpoint reconciliation, backup/restore, or metrics. KubeBlocks treats runtime, script, config, service, and image contracts as immutable after creation, so future runtime contract changes must publish a new `ComponentDefinition` revision instead of patching an existing revision in place.

#### Fixed-address HA writer Endpoint reconciler

Use this route only after the YashanDB/yasboot topology has been built with stable worker addresses. The reconciler watches `yasboot cluster status`, selects exactly one `open/normal/primary`, and patches the writer Endpoint to that node address.

The writer switch is guarded. Before updating the writer Endpoint, the reconciler executes a lightweight SQL write probe inside the candidate primary Pod. If the probe fails, it keeps the previous Endpoint and logs `skip writer switch: primary SQL probe failed`.

Create the password Secret first. Do not put the database password in values files:

```bash
kubectl -n demo create secret generic yashandb-writer-reconciler-auth \
  --from-literal=password='<db-password>'
```

Render or install the addon with the example values file, then replace `clusterName`, `sqlPort`, `endpointPodMap`, and image fields for the target environment:

```bash
helm template yashandb addons/yashandb \
  -n demo \
  -f addons/yashandb/examples/fixed-ha-writer-reconciler-values.yaml
```

```bash
helm upgrade --install yashandb addons/yashandb \
  -n demo \
  -f addons/yashandb/examples/fixed-ha-writer-reconciler-values.yaml
```

The bundled example uses `apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/kubeblocks-tools:1.0.2` because it provides `kubectl` in the target runtime shape. For another offline environment, mirror a kubectl-capable image and update `ha.writerReconciler.image.*`.

Optional automatic failover is disabled by default. Enable it only after the fixed-address topology and writer Endpoint follower have passed validation in the target environment:

```yaml
ha:
  writerReconciler:
    failover:
      enabled: true
      failureThreshold: 5
      cooldownSeconds: 60
```

When enabled, the reconciler uses a conservative failover state machine:

1. It first waits for repeated observations of no `open/normal/primary` and at least one `open/normal/standby`.
2. Before running `yasboot node failover`, it re-checks cluster status because YashanDB may have already completed election.
3. If a new primary appears, it only reconciles the writer Endpoint.
4. If no primary appears, it runs `yasboot node failover` against one visible standby.
5. If YashanDB returns an election conflict such as `YAS-02434`, the reconciler enters cooldown and waits for status convergence instead of repeatedly issuing failover.

It then waits for a new primary and reconciles the writer Endpoint. It does not rebuild the old primary.

After a primary change, the reconciler logs the observed topology and emits `rebuild manual action required` for the previous primary. This is intentionally conservative: the addon does not automatically rebuild an old primary until a safer rebuild contract is validated.

Verify the reconciler and writer Endpoint:

```bash
kubectl -n demo get deploy yashandb-writer-endpoint-reconciler
kubectl -n demo get svc,endpoints yashandb-writer -o wide
kubectl -n demo logs deploy/yashandb-writer-endpoint-reconciler --tail=50
```

Current PR validation boundary:

- Helm renders the optional writer Endpoint reconciler resources.
- Runtime writer endpoint movement, planned switchover, failover behavior, and traffic continuity require target-cluster evidence before promotion.

Claim boundary:

- This is a fixed-address/hostNetwork writer Endpoint follower by default.
- Optional automatic `yasboot node failover` is available only when explicitly enabled. It coordinates with YashanDB election by waiting first, re-checking before failover, and cooling down on election conflict.
- Writer Endpoint updates require both `open/normal/primary` status and a successful SQL write probe on the candidate primary.
- Old-primary rebuild is not automatic. The reconciler reports the manual action boundary after detecting a primary change.
- It does not support generic Pod-IP HA.
- It does not provide full MySQL/PostgreSQL HA parity.

### Backup and Restore

| Feature | Status | Notes |
|---|---|---|
| Full Backup | Template wiring | Uses `backup database full format '<path>'` and uploads the generated backup set from the shared data mount to the KubeBlocks BackupRepository. The source database must be in archive log mode. Current-head runtime backup evidence is not attached to this PR. |
| Restore | Template wiring | KubeBlocks `prepareData` downloads the full backup set, then `initDB.sh` runs `restore database from '<path>'` during NOMOUNT startup and opens the restored database before readiness. Current-head runtime restore evidence is not attached to this PR. |
| PITR | Not implemented | Waiting for archive/log restore contract. |

### Monitoring

| Feature | Status | Notes |
|---|---|---|
| Metrics exporter | Optional sidecar template | Disabled by default. The YCM 23.5.13.3 aarch64 package contains `yashandb_exporter-v0.1.1-159-g906774c-linux-arm64.tar.gz`; build or mirror an image that contains this exporter and create the exporter password Secret before setting `metrics.enabled=true`. |
| Dashboard | Placeholder JSON | Import target exists, but real PromQL panels require a live exporter scrape and confirmed metric labels. |

## Examples

### Create

Create a yashandb cluster of version 'yashandb-personal:23.1.1.100' with ONE replica.

> [!NOTE]
> This is a personal version of YashanDB, for the enterprise version, please contact the vendor.
> The personal version is only for testing and development purposes, and it runs in Standalone mode with only one replica.

```yaml
# cat examples/yashandb/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: yashandb-cluster
  namespace: demo
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: yashan-comp
      componentDef: yashandb-1.2.0-alpha.0
      # Only supports Standalone YashanDB at the moment
      # Must set replcias to 1.
      replicas: 1
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
        requests:
          cpu: "1"
          memory: "1Gi"
```

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

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/yashandb/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: yashandb-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: yashandb-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  # 2026-06-02 Reason: align OpsRequest examples with the Cluster component name; Purpose: keep Stage 1 examples directly applicable to examples/yashandb/cluster.yaml.
  - componentName: yashan-comp
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1.5'
      memory: 1.5Gi
    limits:
      cpu: '1.5'
      memory: 1.5Gi

```

```bash
kubectl apply -f examples/yashandb/verticalscale.yaml
```

### Horizontal scaling

> [!NOTE]
> These examples show the standard KubeBlocks scaling request shape. The current personal image is documented as standalone, so multi-replica behavior must be validated in a real YashanDB environment before it is considered supported.

#### Scale-out

```bash
kubectl apply -f examples/yashandb/scale-out.yaml
```

#### Scale-in

```bash
kubectl apply -f examples/yashandb/scale-in.yaml
```

### Volume expansion

Expand the `data` volume claim template for the YashanDB component:

```bash
kubectl apply -f examples/yashandb/volumeexpand.yaml
```

### Expose

Expose the standalone YashanDB service:

```bash
kubectl apply -f examples/yashandb/expose-enable.yaml
```

Disable the exposed service:

```bash
kubectl apply -f examples/yashandb/expose-disable.yaml
```

### Switchover

> [!NOTE]
> This addon maps `select database_role from v$database` to KubeBlocks roles: `PRIMARY` becomes `primary`, and `STANDBY` becomes `secondary`. YashanDB `alter database switchover` is executed on the selected secondary pod, so replace `instanceName` with a pod currently labeled as `secondary`.

```bash
kubectl apply -f examples/yashandb/switchover.yaml
```

### Full backup

> [!NOTE]
> This path uses the documented YashanDB SQL full backup command and uploads the generated backup set to the KubeBlocks backup repository. The source database must be in archive log mode; otherwise YashanDB returns `YAS-02079` and the backup is rejected instead of uploading an empty archive.

```bash
kubectl apply -f examples/yashandb/backup.yaml
```

### Restore

> [!NOTE]
> The restore path is wired for a new cluster restored from a full backup. The path starts YashanDB in NOMOUNT mode, submits `restore database from '<path>'`, opens the restored database, and requires the readiness probe to see `OPEN`. This PR does not attach current-head runtime evidence for the backup/restore flow. It does not implement PITR, incremental restore, in-place restore, or HA restore.

```bash
kubectl apply -f examples/yashandb/restore.yaml
```

### Monitoring

> [!WARNING]
> The addon renders an opt-in exporter sidecar when `metrics.enabled=true`. It remains disabled by default because the operator must provide an exporter image and a Secret containing the exporter-compatible encrypted database password. This PR does not attach current-head runtime scrape evidence for the sidecar, ServiceMonitor, or dashboard.

The confirmed package path is:

```text
ycm/packages/yashandb_exporter-v0.1.1-159-g906774c-linux-arm64.tar.gz
```

It was found inside:

```text
https://jenkins-tools.yasdb.com/packages/YCM/vmp/23.5/23.5.13.3/yashandb-cloud-manager-23.5.13.3-linux-aarch64.tar.gz
```

The exporter image must contain:

- `yashandb_exporter`;
- `metrics/*.yml`;
- `yashandb-targets.yml`;
- `yasdbpasswd.yml`;
- bundled client libraries under `lib/`.

The exporter reads and locks `yasdbpasswd.yml` during startup, so the addon sidecar does not mount that file directly from a read-only ConfigMap path. It copies target metadata into `/opt/yashandb_exporter/config`, writes the Secret-provided credential into `/opt/yashandb_exporter/config/yasdbpasswd.yml`, and points `--yashandb.targets` plus `--yashandb.operations.users` at the writable copies.

The default addon values now use the confirmed exporter startup contract:

```bash
The sidecar startup contract is:

```bash
yashandb_exporter \
  --web.listen-address=:${EXPORTER_WEB_PORT} \
  --log.level=${EXPORTER_LOG_LEVEL} \
  --web.telemetry-path=/metrics \
  --yashandb.metrics.dir=/opt/yashandb_exporter/metrics-work \
  --yashandb.targets=/opt/yashandb_exporter/config/yashandb-targets.yml \
  --yashandb.operations.users=/opt/yashandb_exporter/config/yasdbpasswd.yml
```

To prepare monitoring:

1. Build or mirror an exporter image from the package above.
2. Set `metrics.image.registry`, `metrics.image.repository`, and `metrics.image.tag` in the addon values.
3. Create a Secret for the exporter credential. The Secret value must be the encrypted password format accepted by `yashandb_exporter`, not the database plaintext password:

```bash
kubectl -n demo create secret generic yashandb-exporter-auth \
  --from-literal=password='<exporter-encrypted-password>'
```

4. Set `metrics.auth.passwordSecretName=yashandb-exporter-auth`.
5. Set `metrics.enabled=true`.
6. Render and install the addon.
7. Apply the PodMonitor example:

```bash
kubectl apply -f examples/yashandb/pod-monitor.yaml
```

Import `dashboards/yashandb.json` only as a placeholder. Replace its text panel with validated PromQL after the exporter is scraped in a real cluster.

Runtime validation in the target cluster should confirm database-backed metrics through the Kubernetes Service, including:

- `yashandb_up 1`
- `yashandb_instance_disconnected ... 0`
- `yashandb_database_database_role ... 1`
- `yashandb_database_status ... 1`
- `yashandb_querys ...`
- `yashandb_exporter_last_scrape_success 1`

One known compatibility risk exists with the bundled `default-se-metrics.yml`: the `swap` metric query references `FREE_SWAP_BLOCKS`, which may not exist in every YashanDB SE database version. The sidecar copies metrics into a writable work directory and disables `swap` by default through `metrics.compat.disabledMetrics`. Keep this as a metric-pack compatibility note until the vendor exporter package or addon provides a version-aware metric override.

### Configure

> [!WARNING]
> Stage 5A only validates and updates static parameters already present in `configs/install.ini.tpl`. All covered parameters are treated as restart-required. Dynamic `ALTER SYSTEM` reload is not wired yet.

```bash
kubectl apply -f examples/yashandb/configure.yaml
```

Covered parameters include `REDO_FILE_SIZE`, `REDO_FILE_NUM`, `INSTALL_SIMPLE_SCHEMA_SALES`, `NLS_CHARACTERSET`, `LISTEN_ADDR`, `DB_BLOCK_SIZE`, `DATA_BUFFER_SIZE`, `SHARE_POOL_SIZE`, `WORK_AREA_POOL_SIZE`, `LARGE_POOL_SIZE`, `REDO_BUFFER_SIZE`, `UNDO_RETENTION`, `OPEN_CURSORS`, `MAX_SESSIONS`, `RUN_LOG_LEVEL`, and `NODE_ID`.

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/yashandb/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: yashandb-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: yashandb-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  # 2026-06-02 Reason: align OpsRequest examples with the Cluster component name; Purpose: keep Stage 1 examples directly applicable to examples/yashandb/cluster.yaml.
  - componentName: yashan-comp

```

```bash
kubectl apply -f examples/yashandb/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/yashandb/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: yashandb-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: yashandb-cluster
  type: Stop

```

```bash
kubectl apply -f examples/yashandb/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/yashandb/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: yashandb-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: yashandb-cluster
  type: Start

```

```bash
kubectl apply -f examples/yashandb/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo yashandb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo yashandb-cluster
```
