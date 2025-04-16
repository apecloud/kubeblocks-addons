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

## Examples

### [Create](cluster.yaml)

Create a yashandb cluster of version 'yashandb-personal:23.1.1.100' with ONE replica.

> [!NOTE]
> This is a personal version of YashanDB, for the enterprise version, please contact the vendor.
> The personal version is only for testing and development purposes, and it runs in Standalone mode with only one replica.

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

 kubectl delete cluster -n demoyashandb-cluster
```
