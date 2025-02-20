# RisingWave

RisingWave is a distributed SQL streaming database that enables cost-efficient and reliable processing of streaming data.

## Prerequisites

This example assumes that you have a Kubernetes cluster installed and running, and that you have installed the kubectl command line tool and helm somewhere in your path. Please see the [getting started](https://kubernetes.io/docs/setup/)  and [Installing Helm](https://helm.sh/docs/intro/install/) for installation instructions for your platform.

Also, this example requires KubeBlocks installed and running. Here is the steps to install KubeBlocks, please replace "`$kb_version`" with the version you want to use.
```bash
# Add Helm repo 
helm repo add kubeblocks https://apecloud.github.io/helm-charts
# If github is not accessible or very slow for you, please use following repo instead
helm repo add kubeblocks https://jihulab.com/api/v4/projects/85949/packages/helm/stable

# Update helm repo
helm repo update

# Get the versions of KubeBlocks and select the one you want to use
helm search repo kubeblocks/kubeblocks --versions
# If you want to obtain the development versions of KubeBlocks, Please add the '--devel' parameter as the following command
helm search repo kubeblocks/kubeblocks --versions --devel

# Create dependent CRDs
kubectl create -f https://github.com/apecloud/kubeblocks/releases/download/v$kb_version/kubeblocks_crds.yaml
# If github is not accessible or very slow for you, please use following command instead
kubectl create -f https://jihulab.com/api/v4/projects/98723/packages/generic/kubeblocks/v$kb_version/kubeblocks_crds.yaml

# Install KubeBlocks
helm install kubeblocks kubeblocks/kubeblocks --namespace kb-system --create-namespace --version="$kb_version"
```
Enable RisingWave
```yaml
# cat examples/risingwave/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: risingwave-cluster
  namespace: demo
  annotations:
    # Create the hummock option
    # RW_STATE_STORE: State store url
    # RW_DATA_DIRECTORY: Remote directory for storing data and metadata objects.
    # RW_ETCD_ENDPOINTS: Etcd endpoint
    # RW_ETCD_AUTH: Enable authentication with etcd.
    kubeblocks.io/extra-env: '{"RW_STATE_STORE":"hummock+minio://kubeblocks:kubeblocks@kb-addon-minio.kb-system.svc:9000/kbcli-test","RW_DATA_DIRECTORY":"risingwave-cluster","RW_ETCD_ENDPOINTS":"etcdr-cluster-etcd.default.svc.cluster.local:2379","RW_ETCD_AUTH":"false"}'
spec:
  # Specifies the behavior when a Cluster is deleted.
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Halt`: Deletes Cluster resources like Pods and Services but retains Persistent Volume Claims (PVCs), allowing for data preservation while stopping other operations.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies a list of ClusterComponentSpec objects used to define the individual components that make up a Cluster. This field allows for detailed configuration of each component within the Cluster.
  # Note: `shardingSpecs` and `componentSpecs` cannot both be empty; at least one must be defined to configure a cluster.
  # ClusterComponentSpec defines the specifications for a Component in a Cluster.
  componentSpecs:
  - name: frontend
    componentDef: risingwave-frontend
    replicas: 1
    resources:
      limits:
        cpu: '0.5'
        memory: 1Gi
      requests:
        cpu: '0.5'
        memory: 1Gi
  - componentDef: risingwave-meta
    name: meta
    replicas: 1
    resources:
      limits:
        cpu: '0.5'
        memory: 1Gi
      requests:
        cpu: '0.5'
        memory: 1Gi
  - componentDef: risingwave-compute
    name: compute
    replicas: 1
    resources:
      limits:
        cpu: '0.5'
        memory: 1Gi
      requests:
        cpu: '0.5'
        memory: 1Gi
  - componentDef: risingwave-compactor
    name: compactor
    replicas: 1
    resources:
      limits:
        cpu: '0.5'
        memory: 1Gi
      requests:
        cpu: '0.5'
        memory: 1Gi
  - componentDef: risingwave-connector
    name: connector
    replicas: 1
    resources:
      limits:
        cpu: '0.5'
        memory: 1Gi
      requests:
        cpu: '0.5'
        memory: 1Gi
---
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: etcdr-cluster
  namespace: demo
spec:
  terminationPolicy: WipeOut
  componentSpecs:
    - name: etcd
      componentDef: etcd
      disableExporter: true
      replicas: 3
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi

```

```bash
kubectl apply -f examples/risingwave/cluster.yaml
```

### [Horizontal scaling](horizontalscale.yaml)
Horizontal scaling out or in specified components replicas in the cluster
```yaml
# cat examples/risingwave/horizontalscale.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: risingwave-horizontalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: risingwave-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - frontend
    # - compute
  - componentName: frontend
    # Specifies the number of total replicas.
    replicas: 2

```

```bash
kubectl apply -f examples/risingwave/horizontalscale.yaml
```

### [Vertical scaling](verticalscale.yaml)
Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster
```yaml
# cat examples/risingwave/verticalscale.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: risingwave-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: risingwave-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling. 
  verticalScaling:
    # - frontend
    # - meta
    # - compute
    # - compactor
    # - connector
  - componentName: meta
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: '2Gi'
    limits:
      cpu: '1'
      memory: '2Gi'

```

```bash
kubectl apply -f examples/risingwave/verticalscale.yaml
```

### [Restart](restart.yaml)
Restart the specified components in the cluster
```yaml
# cat examples/risingwave/restart.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: risingwave-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: risingwave-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: frontend
  # - frontend
  # - meta
  # - compute
  # - compactor
  # - connector- componentName: connector

```

```bash
kubectl apply -f examples/risingwave/restart.yaml
```

### [Stop](stop.yaml)
Stop the cluster and release all the pods of the cluster, but the storage will be reserved
```yaml
# cat examples/risingwave/stop.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: risingwave-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: risingwave-cluster
  type: Stop

```

```bash
kubectl apply -f examples/risingwave/stop.yaml
```

### [Start](start.yaml)
Start the stopped cluster
```yaml
# cat examples/risingwave/start.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: risingwave-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: risingwave-cluster
  type: Start

```

```bash
kubectl apply -f examples/risingwave/start.yaml
```

### Delete
If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster
```bash
kubectl patch cluster risingwave-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster risingwave-cluster

kubectl delete cluster etcdr-cluster
```
