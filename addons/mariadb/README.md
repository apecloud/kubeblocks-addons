# Mariadb

MariaDB is a high performance open source relational database management system that is widely used for web and application servers

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| No (Standalone Only)   | Yes                   | Yes               | Yes       | Yes        | No        | Yes    | No         |

### Versions

| Versions |
|----------|
| 10.6.15 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Zookeeper Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### [Create](cluster.yaml)

Create a mariadb cluster with ONE replica:

```yaml
# cat examples/mariadb/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mariadb-cluster
  namespace: default
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: mariadb
      componentDef: mariadb
      # [!Note]
      # Replicate Mode for MariaDB is not supported yet. Please set replicas to '1'
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

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/mariadb/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mariadb-verticalscaling
  namespace: default
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

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/mariadb/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mariadb-volumeexpansion
  namespace: default
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

### [Restart](restart.yaml)

Restart the specified components in the cluster

```yaml
# cat examples/mariadb/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mariadb-restart
  namespace: default
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

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/mariadb/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mariadb-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mariadb-cluster
  type: Stop

```

```bash
kubectl apply -f examples/mariadb/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```yaml
# cat examples/mariadb/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mariadb-start
  namespace: default
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
kubectl patch cluster mariadb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster mariadb-cluster
```
