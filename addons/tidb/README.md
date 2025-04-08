# TiDB

TiDB is an open-source, cloud-native, distributed, MySQL-Compatible database for elastic scale and real-time analytics.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | Yes               | Yes       | Yes        | No       | Yes    | N/A   |

### Versions

| Versions |
|----------|
| 8.4.0  |
| 7.5.2  |
| 7.1.5  |
| 6.5.10 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- TiDB Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### Create

Create a tidb cluster with specified cluster definition

```yaml
# cat examples/tidb/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: tidb-cluster
  namespace: default
spec:
  clusterDef: tidb
  terminationPolicy: Delete
  topology: cluster
  componentSpecs:
    - name: tidb-pd
      serviceVersion: 7.5.2
      replicas: 3
      resources:
        limits:
          cpu: "2"
          memory: "8Gi"
        requests:
          cpu: "2"
          memory: "8Gi"
      volumeClaimTemplates:
      - name: data
        spec:
          storageClassName: ""
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 20Gi
    - name: tikv
      serviceVersion: 7.5.2
      disableExporter: false
      replicas: 3
      resources:
        limits:
          cpu: "4"
          memory: "16Gi"
        requests:
          cpu: "4"
          memory: "16Gi"
      volumeClaimTemplates:
      - name: data
        spec:
          storageClassName: ""
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 500Gi
    - name: tidb
      serviceVersion: 7.5.2
      disableExporter: false
      replicas: 2
      resources:
        limits:
          cpu: "4"
          memory: "16Gi"
        requests:
          cpu: "4"
          memory: "16Gi"

```

```bash
kubectl apply -f examples/tidb/cluster.yaml
```

### Horizontal scaling

#### Scale-out

```yaml
# cat examples/tidb/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: tidb-scale-out
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: tidb-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - tikv
    # - tidb
  - componentName: tidb
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/tidb/scale-out.yaml
```

#### Scale-in

```yaml
# cat examples/tidb/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: tidb-scale-in
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: tidb-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - tikv
    # - tidb
  - componentName: tidb
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/tidb/scale-in.yaml
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/tidb/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: tidb-verticalscaling
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: tidb-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
    # - pd
    # - tikv
    # - tidb
  - componentName: tidb
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '2'
      memory: 3Gi
    limits:
      cpu: '2'
      memory: 3Gi

```

```bash
kubectl apply -f examples/tidb/verticalscale.yaml
```

### Expand volume

Increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/tidb/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: tidb-volumeexpansion
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: tidb-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
    # - pd
    # - tikv
  - componentName: pd
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/tidb/volumeexpand.yaml
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/tidb/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: tidb-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: tidb-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
    # - pd
    # - tikv
    # - tidb
  - componentName: tidb

```

```bash
kubectl apply -f examples/tidb/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/tidb/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: tidb-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: tidb-cluster
  type: Stop

```

```bash
kubectl apply -f examples/tidb/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/tidb/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: tidb-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: tidb-cluster
  type: Start

```

```bash
kubectl apply -f examples/tidb/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster tidb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster tidb-cluster
```
