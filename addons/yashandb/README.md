# Yashandb

YashanDB is a new database system completely independently designed and developed by SICS. Based on classical database theories, it incorporates original Bounded Evaluation theory, Approximation theory, Parallel Scalability theory and Cross-Modal Fusion Computation theory, supports multiple deployment methods such as stand-alone/primary-standby, shared cluster, and distributed ones, covers OLTP/HTAP/OLAP transactions and analyzes mixed load scenarios, and is fully compatible with privatization and cloud infrastructure, providing clients with one-stop enterprise-level converged data management solutions to meet the needs of key industries such as finance, government, telecommunications and energy for high performance, concurrency and security.

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- YashanDB Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

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
  namespace: default
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: yashan
      componentDef: yashandb
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
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: yashandb-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
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

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/yashandb/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: yashandb-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: yashandb-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
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
  namespace: default
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
  namespace: default
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
kubectl patch cluster yashandb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster yashandb-cluster
```
