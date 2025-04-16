# GreptimeDB

An open-source, cloud-native, distributed time-series database with PromQL/SQL/Python supported.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes (datanode)                  | Yes                   | Yes              | Yes       | Yes        | No       | Yes    | N/A     |

### Versions

| Versions |
|----------|
| 0.3.2 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- GreptimeDB Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

Create a greptimedb cluster

```yaml
# cat examples/greptimedb/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: greptimedb-cluster
  namespace: demo
spec:
  # Specifies the name of the ClusterDefinition to use when creating a Cluster.
  clusterDef: greptimedb
  # Specifies the behavior when a Cluster is deleted.
  # Valid options are: [DoNotTerminate, Delete, WipeOut] (`Halt` is deprecated since KB 0.9)
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies a list of ClusterComponentSpec objects used to define the individual components that make up a Cluster. This field allows for detailed configuration of each component within the Cluster.
  # Note: `shardingSpecs` and `componentSpecs` cannot both be empty; at least one must be defined to configure a cluster.
  # ClusterComponentSpec defines the specifications for a Component in a Cluster.
  componentSpecs:
    - name: frontend
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
    - name: datanode
      replicas: 3
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: datanode
          spec:
            accessModes:
              - ReadWriteOnce
            # The name of the StorageClass required by the claim.
            # If not specified, the StorageClass annotated with
            # `storageclass.kubernetes.io/is-default-class=true` will be used by default
            storageClassName: ""
            resources:
              requests:
                storage: 20Gi
    - name: meta
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: 0.5Gi
        requests:
          cpu: "0.5"
          memory: 0.5Gi
    - name: etcd
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
            # The name of the StorageClass required by the claim.
            # If not specified, the StorageClass annotated with
            # `storageclass.kubernetes.io/is-default-class=true` will be used by default
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi

```

```bash
kubectl apply -f examples/greptimedb/cluster.yaml
```

It will create a greptimedb cluster with four components in orders: `etcd`, `metadata`, `datanode` and  `frontent`.
Datanode is mainly responsible for storing the actual data for GreptimeDB. Metadata is responsible for storing metadata information for GreptimeDB. Frontend is responsible for receiving and processing user requests. Etcd is used as the consensus algorithm component for metadata.

#### How to access the GreptimeDB

To connect to the greptimedb cluster, you can use the following command.

1. poforward the frontend service to access the greptimedb cluster

```bash
# for mysql client
kubectl port-forward svc/greptimedb-cluster-frontend 4002:4002
# for postgresql client
kubectl port-forward svc/greptimedb-cluster-frontend 4003:4003
```

2. Connect to the greptimedb cluster using the client

```bash
# for mysql client
mysql -h 127.0.0.1 -P 4002
# for postgresql client
psql -h 127.0.0.1 -p 4003
```

To visit the dashboard of greptimedb, you can use the following command.

```bash
kubectl port-forward svc/greptimedb-cluster-frontend 4000:4000
```

Then visit the dashboard at `http://localhost:4000/dashboard`.

### Horizontal scaling

#### Scale-out

Horizontal scaling out greptimedb cluster by adding ONE more datanode replica:

```yaml
# cat examples/greptimedb/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: greptimedb-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: greptimedb-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - frontend
    # - datanode
  - componentName: datanode
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/greptimedb/scale-out.yaml
```

#### Scale-in

Horizontal scaling in greptimedb cluster by deleting ONE datanode replica:

```yaml
# cat examples/greptimedb/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: greptimedb-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: greptimedb-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - frontend
    # - datanode
  - componentName: datanode
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/greptimedb/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  clusterDef: greptimedb
  componentSpecs:
  - componentDef: greptimedb-datanode-1.0.0
    name: datanode
    replicas: 4 # update replicas as needed
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 500m
        memory: 512Mi
    serviceVersion: 0.3.2
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/greptimedb/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: greptimedb-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: greptimedb-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: datanode
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/greptimedb/verticalscale.yaml
```

### Expand volume

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created. It is introduced in Kubernetes v1.11 and goes GA in Kubernetes v1.24. It allows Kubernetes users to simply edit their PersistentVolumeClaim objects  without requiring any downtime at all if possible.

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

To increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/greptimedb/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: greptimedb-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: greptimedb-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
  - componentName: datanode
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
      # A reference to the volumeClaimTemplate name from the cluster components.
      # - datanode, datanode
      # - etcd, etcd-storage
    - name: datanode
      storage: 30Gi

```

```bash
kubectl apply -f examples/greptimedb/volumeexpand.yaml
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/greptimedb/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: greptimedb-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: greptimedb-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
    # - frontend
    # - datanode
    # - meta
    # - etcd
  - componentName: frontend

```

```bash
kubectl apply -f examples/greptimedb/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/greptimedb/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: greptimedb-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: greptimedb-cluster
  type: Stop

```

```bash
kubectl apply -f examples/greptimedb/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/greptimedb/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: greptimedb-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: greptimedb-cluster
  type: Start

```

```bash
kubectl apply -f examples/greptimedb/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo greptimedb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

 kubectl delete cluster -n demogreptimedb-cluster
```
