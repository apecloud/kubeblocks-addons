# Orchestrator

Orchestrator is a MySQL high availability and replication management tool, runs as a service and provides command line access, HTTP API and Web interface.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes (Share-Backend Mode) | Yes                   | Yes               | Yes       | Yes        | No        | Yes    | No      |

### Versions

| Versions |
|----------|
| 3.2.6    |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Orchestrator Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### Create

Orchestrator cluster has two modes: *raft* and *share-backend*.

- *share-backend*: Orchestrator cluster with shared backend[^1], here we create an ApeCloud MySQL cluster as the backend. Recommended for large scale.

```yaml
# cat examples/orchestrator/cluster-shared-backend.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: orchestrator-cluster
  namespace: default
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: orchestrator
      componentDef: orchestrator-shared-backend
      replicas: 3
      resources:
        requests:
          cpu: '0.5'
          memory: 0.5Gi
        limits:
          cpu: '0.5'
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
      serviceRefs:
        - name: metadb
          namespace: default
          clusterServiceSelector:
            cluster: mysqlo-cluster
            credential:
              name: root
              component: mysql
            service:
              service: ""
              component: mysql
---
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mysqlo-cluster
  namespace: default
spec:
  terminationPolicy: Delete
  clusterDef: apecloud-mysql
  topology: apecloud-mysql
  componentSpecs:
    - name: mysql
      serviceVersion: "8.0.30"
      disableExporter: false
      replicas: 3
      resources:
        limits:
          cpu: '0.5'
          memory: 0.5Gi
        requests:
          cpu: '0.5'
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
kubectl apply -f examples/orchestrator/cluster-shared-backend.yaml
```

- *raft*: Orchestrator cluster with Raft consensus[^2]. Recommended for small to medium scale.

```yaml
# cat examples/orchestrator/cluster-raft.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: orchestrator-cluster-raft
  namespace: default
spec:
  # Specifies the behavior when a Cluster is deleted.
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Halt`: Deletes Cluster resources like Pods and Services but retains Persistent Volume Claims (PVCs), allowing for data preservation while stopping other operations.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  terminationPolicy: Delete
  # Specifies a list of ClusterComponentSpec objects used to define the individual components that make up a Cluster. This field allows for detailed configuration of each component within the Cluster.
  # Note: `shardingSpecs` and `componentSpecs` cannot both be empty; at least one must be defined to configure a cluster.
  # ClusterComponentSpec defines the specifications for a Component in a Cluster.
  componentSpecs:
    - name: orchestrator
      componentDef: orchestrator-raft
      disableExporter: true
      replicas: 3
      resources:
        requests:
          cpu: '0.5'
          memory: 0.5Gi
        limits:
          cpu: '0.5'
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
kubectl apply -f examples/orchestrator/cluster-raft.yaml
```

Please choose one of the above cluster creation methods according to your needs and scale.

To visit Orchestrator Web UI, you can use the following command to get the service URL:

```bash
kubectl svc/orchestrator-cluster-orchestrator 3000:80
```

Then you can visit the Orchestrator Web UI with the following URL:

```bash
http://localhost:3000
```

### Horizontal scaling

#### Scale-out

> [!IMPORTANT]
> As per the Orchestrator documentation, the number of Orchestrator instances should be odd to avoid split-brain scenarios.
> Make sure the number of Orchestrator instances is always an odd number after scaling in or out.

To scale out the Orchestrator cluster of Share-Backend Mode

```yaml
# cat examples/orchestrator/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orc-scale-out
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orchestrator-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: orchestrator
    # Specifies the replica changes for scaling out components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/orchestrator/scale-out.yaml
```

#### Scale-in

To scale in the Orchestrator cluster of Share-Backend Mode

```yaml
# cat examples/orchestrator/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orc-scale-in
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orchestrator-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: orchestrator
    # Specifies the replica changes for scaling out components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/orchestrator/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: orchestrator
      componentDef: orchestrator-shared-backend
      replicas: 3 # Update `replicas` to your desired number
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/orchestrator/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orchestrator-verticalscaling
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orchestrator-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
    # - orchestrator
  - componentName: orchestrator
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/orchestrator/verticalscale.yaml
```

### Expand volume

Increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/orchestrator/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orchestrator-volumeexpansion
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orchestrator-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: orchestrator
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/orchestrator/volumeexpand.yaml
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/orchestrator/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orchestrator-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orchestrator-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
    # - orchestrator
  - componentName: orchestrator

```

```bash
kubectl apply -f examples/orchestrator/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/orchestrator/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orchestrator-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orchestrator-cluster
  type: Stop

```

```bash
kubectl apply -f examples/orchestrator/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/orchestrator/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orchestrator-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orchestrator-cluster
  type: Start

```

```bash
kubectl apply -f examples/orchestrator/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster orchestrator-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster orchestrator-cluster

# or delete all clusters created in this example
# you may use the following command:
# kubectl delete -f examples/orchestrator/cluster-shared-backend.yaml
# kubectl delete -f examples/orchestrator/cluster-raft.yaml
```

### Reference

[^1]: Shared Backend, https://github.com/openark/orchestrator/blob/master/docs/deployment-shared-backend.md
[^2]: Raft, https://github.com/openark/orchestrator/blob/master/docs/deployment-raft.md
