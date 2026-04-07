# Dolt

[Dolt](https://github.com/dolthub/dolt) is a MySQL-compatible SQL database with Git-style versioning. This addon runs `dolt sql-server` in replication (primary / standby) or standalone mode.

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Dolt Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Install addon

```bash
helm install dolt ./addons/dolt -n kb-system
```

Adjust `kb-system` to the namespace where your KubeBlocks addons are installed.

## Examples

### Create a primary / standby cluster

[`cluster-replication.yaml`](cluster-replication.yaml) creates a two-replica Dolt replication cluster (Dolt primary + standby).

```bash
kubectl apply -f examples/dolt/cluster-replication.yaml
```

Check supported versions:

```bash
kubectl get cmpv dolt
```

Match `spec.componentSpecs[].componentDef` to the addon (`dolt-replication` or `dolt-standalone`), and `serviceVersion` to a release in that ComponentVersion (for example `1.84.0`).

#### Switchover

After the cluster is healthy, trigger a planned switchover so another replica becomes primary.

**With explicit candidate** — [`switchover-specified-instance.yaml`](switchover-specified-instance.yaml):

```bash
kubectl apply -f examples/dolt/switchover-specified-instance.yaml
```

Edit `instanceName` / `candidateName` to match your pod names (`<clusterName>-dolt-<ordinal>`). Get pods:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=dolt-repl -L kubeblocks.io/role
```

### Create a single-node (standalone) cluster

[`cluster-standalone.yaml`](cluster-standalone.yaml) uses the standalone ComponentDefinition (exactly one replica).

```bash
kubectl apply -f examples/dolt/cluster-standalone.yaml
```

Switchover does not apply to standalone topology (single replica).

### Create a Dolt replica of a MySQL cluster

Dolt can act as a [versioned MySQL replica](https://docs.dolthub.com/introduction/getting-started/versioned-mysql-replica) — it consumes MySQL binlog events and automatically creates Dolt commits, giving you time travel, diff, and rollback on every write that happens on the MySQL primary.

[`cluster-mysql-replica.yaml`](cluster-mysql-replica.yaml) deploys two clusters:

1. **mysql-source** — a standalone MySQL 8.0 cluster (the replication primary)
2. **dolt-mysql-replica** — a standalone Dolt cluster that references the MySQL cluster via `serviceRefs`

```bash
kubectl apply -f examples/dolt/cluster-mysql-replica.yaml
```

Wait for both clusters to become ready:

```bash
kubectl -n demo get cluster mysql-source dolt-mysql-replica
```

#### Verify replication

Connect to the **MySQL primary** and create some data:

```bash
# get the mysql root password
MYSQL_ROOT_PASSWORD=$(kubectl -n demo get secret mysql-source-mysql-account-root \
  -o jsonpath='{.data.password}' | base64 -d)

# connect to MySQL
kubectl -n demo exec -it mysql-source-mysql-0 -- \
  mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
    CREATE DATABASE foo;
    USE foo;
    CREATE TABLE t (c1 INT PRIMARY KEY, c2 INT);
    INSERT INTO t VALUES (1, 100), (2, 200), (3, 300);
  "
```

Connect to the **Dolt replica** and confirm the data has replicated:

```bash
kubectl -n demo exec -it dolt-mysql-replica-dolt-0 -- \
  dolt --host 127.0.0.1 --port 3306 --no-tls sql -q "USE foo; SELECT * FROM t;"
```

You should see the three rows from the MySQL primary.

#### Inspect the Dolt commit log

Every replicated transaction becomes a Dolt commit. Query the version history:

```bash
kubectl -n demo exec -it dolt-mysql-replica-dolt-0 -- \
  dolt --host 127.0.0.1 --port 3306 --no-tls sql -q "USE foo; SELECT * FROM dolt_log;"
```

#### Inspect diffs

See exactly what changed in the last commit using the `dolt_diff()` table function:

```bash
kubectl -n demo exec -it dolt-mysql-replica-dolt-0 -- \
  dolt --host 127.0.0.1 --port 3306 --no-tls sql -q "
    USE foo;
    SELECT * FROM dolt_diff('HEAD^', 'HEAD', 't');
  "
```

#### Find and revert a bad change

Make a bad change on the MySQL primary:

```bash
kubectl -n demo exec -it mysql-source-mysql-0 -- \
  mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
    USE foo;
    UPDATE t SET c2 = 0 WHERE c1 = 2;
  "
```

On the Dolt replica, identify the bad commit and generate a revert patch:

```bash
kubectl -n demo exec -it dolt-mysql-replica-dolt-0 -- \
  dolt --host 127.0.0.1 --port 3306 --no-tls sql -q "
    USE foo;
    SELECT * FROM dolt_diff('HEAD^', 'HEAD', 't');
    SELECT statement FROM dolt_patch('HEAD', 'HEAD^');
  "
```

The `dolt_patch()` output gives you the exact SQL statements to run on the MySQL primary to revert the change. Apply them to the primary to restore the original data.

#### Check replication status

```bash
kubectl -n demo exec -it dolt-mysql-replica-dolt-0 -- \
  dolt --host 127.0.0.1 --port 3306 --no-tls sql -q "SHOW REPLICA STATUS"
```
