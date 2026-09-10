# DoltDB

DoltDB is a MySQL-compatible SQL database with Git-style versioning. This example shows how to run Dolt SQL Server on Kubernetes with KubeBlocks.

The addon exposes `standalone` and `replication` topologies. A standalone DoltDB cluster can optionally bind ServiceRef `mysql-source` to run as a binlog replica of a MySQL source. `replication` runs one primary and one to five Dolt standbys.

## Features In KubeBlocks

### Lifecycle Management

| Topology | Replicas | Horizontal scaling | Switchover | Failover | Vertical scaling | Expand volume | Restart | Stop/Start | Configure | Expose |
|----------|----------|-------------------|------------|----------|------------------|---------------|---------|------------|-----------|--------|
| standalone | 1 | No | No | No | Yes | Yes | Yes | Yes | Cluster API | Yes |
| replication | 1 primary + 1..5 standbys | Yes, standby scale-in/out | Yes, controlled | No | Yes | Yes | Yes | Yes | Cluster API | Primary SQL service |

### Backup and Restore

| Feature | Method | Description |
|---------|--------|-------------|
| Logical backup | dolt-backup | Lists current databases through SQL, stages each Dolt database repository on the target data volume, and syncs through `dolt_backup('sync-url', ...)` |

Restore from `dolt-backup` is supported for standalone and replication clusters through `Cluster.spec.restore`. KubeBlocks creates the DataProtection `Restore` CR automatically when the restored component reaches the post-ready stage. Replication backup targets the current primary; restore-post creates an empty Dolt commit per restored database to trigger standby catch-up without changing table rows.

The restore examples set `dataprotection.kubeblocks.io/source-target-name: doltdb` so KubeBlocks uses the recorded DoltDB backup source target directly when restoring into a different cluster name.

Backup and restore examples currently cover non-TLS clusters. TLS-enabled backup or restore is not supported in this addon version because DataProtection job containers do not mount the generated KubeBlocks CA or set `SSL_CERT_FILE`.

### Versions

| Major Versions | Description |
|---------------|-------------|
| 2.1 | 2.1.10 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- DoltDB Addon enabled, refer to [Install Addons](../docs/install-addon.md)
- Create namespace `demo`:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

Create a single-node DoltDB cluster with an initial database named `testdb`:

```bash
kubectl apply -f examples/doltdb/cluster.yaml
```

Check cluster and pod status:

```bash
kubectl get -n demo cluster doltdb-cluster
kubectl get pod -n demo -l app.kubernetes.io/instance=doltdb-cluster,apps.kubeblocks.io/component-name=doltdb
```

Connect with the Dolt CLI from a temporary client Pod:

```bash
ROOT_PASSWORD="$(kubectl get secret -n demo doltdb-cluster-doltdb-account-root -o jsonpath='{.data.password}' | base64 --decode)"
SERVICE="$(kubectl get svc -n demo -l app.kubernetes.io/instance=doltdb-cluster,apps.kubeblocks.io/component-name=doltdb -o jsonpath='{.items[?(@.spec.clusterIP!="None")].metadata.name}')"

kubectl run -n demo doltdb-client --rm -it --restart=Never \
  --image=docker.io/dolthub/dolt-sql-server:2.1.10 \
  -- dolt --host="${SERVICE}.demo.svc" --port=3306 --user=root \
  --password="${ROOT_PASSWORD}" --no-tls \
  sql --query="USE testdb; SHOW TABLES;" --result-format=csv
```

When TLS is enabled, omit `--no-tls`, make the client trust the generated CA, and connect through a hostname covered by the generated certificate. The generated certificate may not cover the ClusterIP Service DNS name; use the Pod headless DNS name from a client Pod, or `localhost` / `127.0.0.1` from inside the target Pod.

### [Create MySQL source replica](cluster-mysql-replica.yaml)

Create a single-node standalone DoltDB cluster that uses ServiceRef `mysql-source` to consume binlog events from a MySQL source. This is not a separate KubeBlocks topology; it uses `topology: standalone` plus a ServiceRef binding and replica env settings.

For the addons-cluster chart, keep `topology=standalone` and set `mysqlSource.enabled=true` with either a source Cluster selector or ServiceDescriptor. The chart release name must be no more than 15 characters; the commands below use `dolt-mysql-repl`.

Create or reuse a KubeBlocks MySQL Cluster named `mysql-cluster` in namespace `demo`:

```bash
kubectl apply -f examples/mysql/cluster.yaml
kubectl wait -n demo --for=condition=Ready cluster/mysql-cluster --timeout=10m
```

Prepare the MySQL source for Dolt replication. Dolt requires row-based binlogs and GTID auto-positioning. The MySQL example cluster already enables GTID, but its default `binlog_format` may be `MIXED`, so change it with a Reconfiguring OpsRequest:

```bash
kubectl apply -f - <<'EOF'
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-binlog-format-row
  namespace: demo
spec:
  clusterName: mysql-cluster
  force: false
  reconfigures:
  - componentName: mysql
    parameters:
    - key: binlog_format
      value: ROW
  preConditionDeadlineSeconds: 0
  type: Reconfiguring
EOF

kubectl wait -n demo --for=jsonpath='{.status.phase}'=Succeed \
  opsrequest/mysql-binlog-format-row --timeout=300s
```

Verify the source before creating DoltDB:

```bash
MYSQL_ROOT_PASSWORD="$(kubectl get secret -n demo mysql-cluster-mysql-account-root -o jsonpath='{.data.password}' | base64 --decode)"
PRIMARY_POD="$(kubectl get pod -n demo \
  -l app.kubernetes.io/instance=mysql-cluster,apps.kubeblocks.io/component-name=mysql,kubeblocks.io/role=primary \
  -o jsonpath='{.items[0].metadata.name}')"

kubectl exec -n demo "$PRIMARY_POD" -c mysql -- \
  env MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql -uroot -Nse \
  "SHOW VARIABLES WHERE Variable_name IN ('binlog_format','enforce_gtid_consistency','gtid_mode','server_id');
   SELECT 'GTID_PURGED', @@GLOBAL.gtid_purged;
   SHOW GRANTS FOR 'kbreplicator'@'%';"
```

Expected source settings:

- `binlog_format=ROW`
- `enforce_gtid_consistency=ON`
- `gtid_mode=ON`
- `server_id` is non-zero
- `GTID_PURGED` is empty
- `kbreplicator` has replication permission

Seed source data that the Dolt replica can later prove it has received:

```bash
kubectl exec -n demo "$PRIMARY_POD" -c mysql -- \
  env MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql -uroot -Nse \
  "CREATE DATABASE IF NOT EXISTS testdb;
   CREATE TABLE IF NOT EXISTS testdb.kb_smoke (id INT PRIMARY KEY, note VARCHAR(64));
   REPLACE INTO testdb.kb_smoke (id,note) VALUES (101,'mysql-to-dolt-ok');
   SELECT id,note FROM testdb.kb_smoke WHERE id=101;"
```

Start DoltDB with a ServiceRef to the MySQL source through the addons-cluster chart:

```bash
helm upgrade --install dolt-mysql-repl ./addons-cluster/doltdb -n demo \
  --set topology=standalone \
  --set database=testdb \
  --set mysqlSource.enabled=true \
  --set mysqlSource.replicaServerId=123 \
  --set mysqlSource.serviceRef.namespace=demo \
  --set mysqlSource.serviceRef.clusterServiceSelector.cluster=mysql-cluster \
  --set mysqlSource.serviceRef.clusterServiceSelector.credential.name=kbreplicator

kubectl wait -n demo --for=condition=Ready cluster/dolt-mysql-repl --timeout=10m
```

For a raw Cluster manifest backed by another KubeBlocks MySQL Cluster, update `cluster-mysql-replica.yaml` with the source Cluster name, service selector, and credential selector, then apply it. The checked-in manifest targets `mysql-cluster` and uses the narrower `kbreplicator` credential:

```bash
kubectl apply -f examples/doltdb/cluster-mysql-replica.yaml
```

If you use the raw manifest instead of the Helm chart, set `DOLT_CLUSTER=doltdb-mysql-replica` in the verification commands below.

> [!IMPORTANT]
> The MySQL source must already use row-based binlog replication, GTID auto-positioning, and a non-zero `server_id`. The Dolt replica must use a positive `DOLT_MYSQL_REPLICA_SERVER_ID` that is unique across the source and any replicas. If the source has purged binlog history, warm the Dolt replica manually with a consistent dump before starting replication.

For your own MySQL server, create a replication account on the source, update `mysql-source-servicedescriptor.yaml` with the source host, port, username, and password Secret, then apply the external-source flow:

```bash
kubectl apply -f examples/doltdb/mysql-source-servicedescriptor.yaml
kubectl apply -f examples/doltdb/cluster-mysql-replica-external.yaml
```

The raw standalone Cluster manifest must include all three MySQL-source replica pieces:

- `spec.componentSpecs[].serviceRefs[]` with name `mysql-source`;
- `DOLT_MYSQL_REPLICA_REQUIRED=true`, so a missing ServiceRef fails provisioning instead of creating a non-replicating DoltDB;
- a unique positive `DOLT_MYSQL_REPLICA_SERVER_ID`.

The current ServiceRef declaration accepts `serviceKind: mysql`. MariaDB-specific `serviceKind: mariadb` binding is not implemented in this addon version.

This mode configures Dolt once through the component `postProvision` lifecycle action by running `CHANGE REPLICATION SOURCE TO ...` and `START REPLICA` after the Dolt runtime is ready. Before the action reports success, it checks `SHOW REPLICA STATUS` and waits for the IO and SQL replication threads to run. Source credentials come from the ServiceRef binding. MySQL source TLS, automatic dump/import, replication drift detection, Day-2 source switching, credential rotation, and automatic repair are not supported in this addon version. Dolt's current MySQL-source replication also supports only the default replication channel, only `REPLICATE_DO_TABLE` / `REPLICATE_IGNORE_TABLE` filter options, and does not validate replication checksums. Optional replication filters are initial-provisioning only and are not guaranteed after Pod restart.

Check replica status from the Dolt Pod:

```bash
DOLT_CLUSTER=dolt-mysql-repl
POD="$(kubectl get pod -n demo -l app.kubernetes.io/instance="${DOLT_CLUSTER}",apps.kubeblocks.io/component-name=doltdb -o jsonpath='{.items[0].metadata.name}')"
ROOT_PASSWORD="$(kubectl get secret -n demo "${DOLT_CLUSTER}-doltdb-account-root" -o jsonpath='{.data.password}' | base64 --decode)"
kubectl exec -n demo "$POD" -c doltdb -- \
  dolt --host=127.0.0.1 --port=3306 --user=root --password="${ROOT_PASSWORD}" --no-tls \
  sql --query="SHOW REPLICA STATUS;" --result-format=vertical
```

`Replica_IO_Running` and `Replica_SQL_Running` should both be `Yes`, and `Auto_Position` should be `1`.

Verify replicated data from DoltDB:

```bash
kubectl exec -n demo "$POD" -c doltdb -- \
  dolt --host=127.0.0.1 --port=3306 --user=root --password="${ROOT_PASSWORD}" --no-tls \
  sql --query="USE testdb; SELECT id,note FROM kb_smoke WHERE id=101;" --result-format=csv
```

Expected result:

```text
id,note
101,mysql-to-dolt-ok
```

### [Create replication topology](cluster-replication.yaml)

Create a DoltDB cluster with one primary and one standby:

```bash
kubectl apply -f examples/doltdb/cluster-replication.yaml
```

Check Dolt roles reported by KubeBlocks:

```bash
kubectl get pod -n demo \
  -l app.kubernetes.io/instance=doltdb-replication,apps.kubeblocks.io/component-name=doltdb \
  --show-labels
```

The default SQL service routes to the `primary` role. Standbys are read-only and receive committed writes from the primary. Controlled switchover is supported. Automatic failover and failback are intentionally not supported.

### Monitoring

Dolt native Prometheus metrics are enabled on the `metrics` port (`11228`) at `/metrics`. You can verify the endpoint directly from the main container without a local Prometheus or PodMonitor:

```bash
POD="$(kubectl get pod -n demo -l app.kubernetes.io/instance=doltdb-cluster,apps.kubeblocks.io/component-name=doltdb --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
kubectl exec -n demo "$POD" -c doltdb -- /usr/bin/curl -fsS http://127.0.0.1:11228/metrics \
  | grep -E 'dss_(dolt_version|concurrent_connections|is_replica|replication_lag)'
```

Replication clusters should expose `dss_is_replica` and `dss_replication_lag` after data has been written and replicated. The addon does not ship a Grafana dashboard because no official Dolt dashboard was found. If you import a custom dashboard, build variables from the actual scraped labels, especially KubeBlocks pod labels and Dolt's `namespace`, `cluster`, and `component` metric labels.

### [Scale out replication](scale-out.yaml)

Add one standby to a replication cluster:

```bash
kubectl apply -f examples/doltdb/scale-out.yaml
```

The addon renders replication peer variables into the config template so KubeBlocks restarts the component after the peer list changes. After restart, every Pod regenerates its Dolt `cluster.standby_remotes` list from the current component Pod FQDN list.

### [Scale in specified standby](scale-in-specified-standby.yaml)

Scale-in must target a standby explicitly:

```bash
kubectl apply -f examples/doltdb/scale-in-specified-standby.yaml
```

Before applying, set `onlineInstancesToOffline` to a current standby Pod name. Do not target the current primary. Use the role labels or `/scripts/doltdb-role-probe.sh` to confirm the target role first.

### [Switchover replication](switchover.yaml)

Controlled switchover transfers the primary role to a selected standby. During a controlled demotion, Dolt blocks until final replication to each standby completes or fails, so keep the old primary reachable until the OpsRequest completes. Automatic failover and failback are not supported.

Check the current role labels and edit `instanceName` / `candidateName` in `switchover.yaml` before applying:

```bash
kubectl get pod -n demo \
  -l app.kubernetes.io/instance=doltdb-replication,apps.kubeblocks.io/component-name=doltdb \
  -L kubeblocks.io/role

kubectl apply -f examples/doltdb/switchover.yaml
kubectl wait -n demo --for=jsonpath='{.status.phase}'=Succeed \
  opsrequest/doltdb-replication-switchover --timeout=300s
```

After a switchover, `doltdb-replication-doltdb-0` may be a standby. Restarts preserve Dolt's persisted role state instead of recalculating roles from ordinal.

### [Restart replication](restart-replication.yaml)

Restart all replication Pods, for example after a controlled switchover:

```bash
kubectl apply -f examples/doltdb/restart-replication.yaml
kubectl wait -n demo --for=jsonpath='{.status.phase}'=Succeed \
  opsrequest/doltdb-replication-restart --timeout=300s
```

### [Configure through Cluster API](cluster-with-config.yaml)

DoltDB server settings are rendered into the pod-local server config from `spec.componentSpecs[].configs[].variables`. Changes restart the component.

```bash
kubectl apply -f examples/doltdb/cluster-with-config.yaml
```

To update configuration later, edit the Cluster variables and re-apply. For example, change `DOLT_LOG_LEVEL` from `debug` to `warning`:

```yaml
configs:
  - name: doltdb-server-config
    restart: true
    variables:
      DOLT_LOG_LEVEL: warning
```

> [!IMPORTANT]
> `read_timeout_millis` and `write_timeout_millis` are stored in milliseconds but applied as second-based SQL timeouts. Use whole-second values such as `12000`, not values like `12345`.

OpsRequest-based reconfiguration is not supported in the current addon version.

### [Create with TLS](cluster-tls.yaml)

Enable KubeBlocks-managed TLS for the SQL listener:

```bash
kubectl apply -f examples/doltdb/cluster-tls.yaml
```

This example covers the SQL listener. Dolt clients must trust the generated CA and connect through a hostname covered by the generated certificate, such as the Pod headless DNS name. Direct-to-standby replication peers use the addon-managed internal remotesapi addresses.

TLS support is intentionally scoped:

- Supported and verified: SQL listener TLS for probes, role checks, switchover SQL actions, and e2e client Pods that use the generated CA and a SAN-covered host.
- Not covered by TLS: direct-to-standby remotesapi replication, which remains an internal `http://<pod-fqdn>:50051/{database}` path.
- Not covered by TLS: native metrics on `/metrics`, which remain HTTP.
- Not supported: backup and restore against TLS-enabled clusters. Use the backup and restore examples with non-TLS clusters until DataProtection jobs mount and trust the generated CA.

### [Vertical scaling](verticalscale.yaml)

```bash
kubectl apply -f examples/doltdb/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Make sure your StorageClass supports volume expansion before applying this example.

```bash
kubectl apply -f examples/doltdb/volumeexpand.yaml
```

### [Restart](restart.yaml)

```bash
kubectl apply -f examples/doltdb/restart.yaml
```

### [Stop](stop.yaml)

```bash
kubectl apply -f examples/doltdb/stop.yaml
```

### [Start](start.yaml)

```bash
kubectl apply -f examples/doltdb/start.yaml
```

### [Backup standalone](backup.yaml)

> [!IMPORTANT]
> Create a `BackupRepo` before running backups. Refer to [BackupRepo](../docs/create-backuprepo.md).

Write and commit sample data on the standalone source cluster before creating a backup:

```bash
SOURCE_CLUSTER=doltdb-cluster
CLIENT_IMAGE=docker.io/dolthub/dolt-sql-server:2.1.10
ROOT_PASSWORD="$(kubectl get secret -n demo "${SOURCE_CLUSTER}-doltdb-account-root" -o jsonpath='{.data.password}' | base64 --decode)"
SERVICE="$(kubectl get svc -n demo -l app.kubernetes.io/instance="${SOURCE_CLUSTER}",apps.kubeblocks.io/component-name=doltdb -o jsonpath='{.items[?(@.spec.clusterIP!="None")].metadata.name}')"

run_sql() {
  local query="$1"
  local sql="USE testdb; ${query}"
  kubectl run -n demo doltdb-client --rm -i --restart=Never --image="${CLIENT_IMAGE}" -- \
    dolt --host="${SERVICE}.demo.svc" --port=3306 --user=root \
    --password="${ROOT_PASSWORD}" --no-tls \
    sql "--query=${sql}" --result-format=csv
}

run_sql "CREATE TABLE IF NOT EXISTS kb_smoke (id int primary key, note varchar(64));"
run_sql "REPLACE INTO kb_smoke VALUES (1, 'standalone-ok');"
run_sql "CALL DOLT_ADD('-A');"
run_sql "CALL DOLT_COMMIT('-m', 'example standalone backup');"
```

Create the backup:

```bash
kubectl apply -f examples/doltdb/backup.yaml
kubectl wait -n demo --for=jsonpath='{.status.phase}'=Completed backup/doltdb-cluster-backup --timeout=300s
```

Supported backup methods on the cluster BackupPolicy:

```bash
kubectl get backuppolicy -n demo doltdb-cluster-doltdb-backup-policy -oyaml | yq '.spec.backupMethods[].name'
```

Expected methods:

```text
dolt-backup
```

### [Backup replication](backup-replication.yaml)

Replication backup uses the current primary target from the generated BackupPolicy. The generated BackupPolicy name still follows `<cluster-name>-doltdb-backup-policy`.

Seed data in the default database and a second database so the backup covers every current Dolt database:

```bash
SOURCE_CLUSTER=doltdb-replication
CLIENT_IMAGE=docker.io/dolthub/dolt-sql-server:2.1.10
ROOT_PASSWORD="$(kubectl get secret -n demo "${SOURCE_CLUSTER}-doltdb-account-root" -o jsonpath='{.data.password}' | base64 --decode)"
SERVICE="$(kubectl get svc -n demo -l app.kubernetes.io/instance="${SOURCE_CLUSTER}",apps.kubeblocks.io/component-name=doltdb -o jsonpath='{.items[?(@.spec.clusterIP!="None")].metadata.name}')"

run_sql() {
  local query="$1"
  local database="${2:-testdb}"
  local sql="${query}"
  if [ -n "$database" ]; then
    sql="USE ${database}; ${query}"
  fi
  kubectl run -n demo doltdb-client --rm -i --restart=Never --image="${CLIENT_IMAGE}" -- \
    dolt --host="${SERVICE}.demo.svc" --port=3306 --user=root \
    --password="${ROOT_PASSWORD}" --no-tls \
    sql "--query=${sql}" --result-format=csv
}

run_sql "CREATE TABLE IF NOT EXISTS kb_smoke (id int primary key, note varchar(64));"
run_sql "REPLACE INTO kb_smoke VALUES (1, 'replication-ok');"
run_sql "CALL DOLT_ADD('-A');"
run_sql "CALL DOLT_COMMIT('-m', 'example replication backup');"

run_sql "CREATE DATABASE IF NOT EXISTS auditdb;" ""
run_sql "CREATE TABLE IF NOT EXISTS kb_smoke (id int primary key, note varchar(64));" auditdb
run_sql "REPLACE INTO kb_smoke VALUES (10, 'audit-ok');" auditdb
run_sql "CALL DOLT_ADD('-A');" auditdb
run_sql "CALL DOLT_COMMIT('-m', 'example audit backup');" auditdb
```

Create the replication backup:

```bash
kubectl apply -f examples/doltdb/backup-replication.yaml
kubectl wait -n demo --for=jsonpath='{.status.phase}'=Completed \
  backup/doltdb-replication-backup --timeout=300s
```

### [Restore standalone](restore.yaml)

Create a new one-replica target cluster from the completed backup, then wait for the automatic post-ready restore action:

```bash
kubectl apply -f examples/doltdb/restore.yaml

kubectl wait -n demo --for=condition=Ready pod \
  -l app.kubernetes.io/instance=doltdb-cluster-restore,apps.kubeblocks.io/component-name=doltdb --timeout=300s

RESTORE="$(kubectl get restore -n demo \
  -l dataprotection.kubeblocks.io/backup-name=doltdb-cluster-backup,app.kubernetes.io/instance=doltdb-cluster-restore \
  -o go-template='{{range .items}}{{if .spec.readyConfig}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | head -n 1)"
kubectl wait -n demo --for=jsonpath='{.status.phase}'=Completed "restore/${RESTORE}" --timeout=300s
```

Verify the restored data through a remote Dolt client:

```bash
RESTORE_CLUSTER=doltdb-cluster-restore
CLIENT_IMAGE=docker.io/dolthub/dolt-sql-server:2.1.10
ROOT_PASSWORD="$(kubectl get secret -n demo "${RESTORE_CLUSTER}-doltdb-account-root" -o jsonpath='{.data.password}' | base64 --decode)"
SERVICE="$(kubectl get svc -n demo -l app.kubernetes.io/instance="${RESTORE_CLUSTER}",apps.kubeblocks.io/component-name=doltdb -o jsonpath='{.items[?(@.spec.clusterIP!="None")].metadata.name}')"

kubectl run -n demo doltdb-client --rm -i --restart=Never --image="${CLIENT_IMAGE}" -- \
  dolt --host="${SERVICE}.demo.svc" --port=3306 --user=root \
  --password="${ROOT_PASSWORD}" --no-tls \
  sql --query="USE testdb; SELECT id,note FROM kb_smoke ORDER BY id;" --result-format=csv
```

### [Restore replication](restore-replication.yaml)

Create a new primary/standby target cluster from the completed backup, then wait for the automatic post-ready restore action:

```bash
kubectl apply -f examples/doltdb/restore-replication.yaml

kubectl wait -n demo --for=condition=Ready pod \
  -l app.kubernetes.io/instance=doltdb-replication-restore,apps.kubeblocks.io/component-name=doltdb --timeout=300s

RESTORE="$(kubectl get restore -n demo \
  -l dataprotection.kubeblocks.io/backup-name=doltdb-replication-backup,app.kubernetes.io/instance=doltdb-replication-restore \
  -o go-template='{{range .items}}{{if .spec.readyConfig}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | head -n 1)"
kubectl wait -n demo --for=jsonpath='{.status.phase}'=Completed "restore/${RESTORE}" --timeout=300s
```

KubeBlocks selects the restored primary for post-ready restore from the component role labels. After restoring each database, the addon creates an empty Dolt commit on the restored primary to trigger standby catch-up.

Verify restored data on every restored Pod through a remote Dolt client:

```bash
RESTORE_CLUSTER=doltdb-replication-restore
CLIENT_IMAGE=docker.io/dolthub/dolt-sql-server:2.1.10
ROOT_PASSWORD="$(kubectl get secret -n demo "${RESTORE_CLUSTER}-doltdb-account-root" -o jsonpath='{.data.password}' | base64 --decode)"

for POD in $(kubectl get pod -n demo \
  -l app.kubernetes.io/instance="${RESTORE_CLUSTER}",apps.kubeblocks.io/component-name=doltdb \
  --field-selector=status.phase=Running \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
  HOST="$(kubectl get pod -n demo "${POD}" -o jsonpath='{.status.podIP}')"
  kubectl run -n demo doltdb-client --rm -i --restart=Never --image="${CLIENT_IMAGE}" -- \
    dolt --host="${HOST}" --port=3306 --user=root \
    --password="${ROOT_PASSWORD}" --no-tls \
    sql --query="USE testdb; SELECT id,note FROM kb_smoke ORDER BY id;" --result-format=csv

  kubectl run -n demo doltdb-client --rm -i --restart=Never --image="${CLIENT_IMAGE}" -- \
    dolt --host="${HOST}" --port=3306 --user=root \
    --password="${ROOT_PASSWORD}" --no-tls \
    sql --query="USE auditdb; SELECT id,note FROM kb_smoke ORDER BY id;" --result-format=csv
done
```

## Delete

To delete the cluster and its PVCs:

```bash
kubectl delete cluster -n demo doltdb-cluster
helm uninstall -n demo dolt-mysql-repl
kubectl delete cluster -n demo doltdb-mysql-replica
kubectl delete cluster -n demo doltdb-mysql-replica-external
kubectl delete cluster -n demo doltdb-cluster-restore
kubectl delete cluster -n demo doltdb-replication
kubectl delete cluster -n demo doltdb-replication-restore
kubectl delete opsrequest -n demo mysql-binlog-format-row
kubectl delete servicedescriptor -n demo external-mysql-source
kubectl delete secret -n demo external-mysql-source-auth
```

To also remove backup data from the repository when deleting the Backup CR, keep `deletionPolicy: Delete` in `backup.yaml` and `backup-replication.yaml`.
