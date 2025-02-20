# Orioledb

OrioleDB is a new storage engine for PostgreSQL, bringing a modern approach to database capacity, capabilities and performance to the world's most-loved database platform.

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
Enable orioledb
```yaml
# cat examples/orioledb/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: orioledb-cluster
  namespace: demo
spec:
  # Specifies the name of the ClusterDefinition to use when creating a Cluster.
  clusterDefinitionRef: orioledb
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
  - name: orioledb
    componentDefRef: orioledb
    serviceRefs:
    - name: etcdService
      cluster: etcdo-cluster
      namespace: demo
    replicas: 1
    resources:
      limits:
        cpu: '0.5'
        memory: 1Gi
      requests:
        cpu: '0.5'
        memory: 1Gi
    volumeClaimTemplates:
    - name: data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi
---
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: etcdo-cluster
  namespace: demo
spec:
  clusterDefinitionRef: etcd
  clusterVersionRef: etcd-v3.5.6
  terminationPolicy: WipeOut
  componentSpecs:
  - name: etcd
    componentDefRef: etcd
    replicas: 1
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
        storageClassName: null
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi

```

```bash
kubectl apply -f examples/orioledb/cluster.yaml
```

### [Horizontal scaling](horizontalscale.yaml)
Horizontal scaling out or in specified components replicas in the cluster
```yaml
# cat examples/orioledb/horizontalscale.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orioledb-horizontalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orioledb-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - frontend
    # - compute
  - componentName: orioledb
    # Specifies the number of total replicas.
    replicas: 2

```

```bash
kubectl apply -f examples/orioledb/horizontalscale.yaml
```

### [Vertical scaling](verticalscale.yaml)
Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster
```yaml
# cat examples/orioledb/verticalscale.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orioledb-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orioledb-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling. 
  verticalScaling:
  - componentName: orioledb
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: '2Gi'
    limits:
      cpu: '1'
      memory: '2Gi'

```

```bash
kubectl apply -f examples/orioledb/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)
Increase size of volume storage with the specified components in the cluster
```yaml
# cat examples/orioledb/volumeexpand.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orioledb-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orioledb-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion. 
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: orioledb
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/orioledb/volumeexpand.yaml
```

### [Restart](restart.yaml)
Restart the specified components in the cluster
```yaml
# cat examples/orioledb/restart.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orioledb-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orioledb-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: orioledb

```

```bash
kubectl apply -f examples/orioledb/restart.yaml
```

### [Stop](stop.yaml)
Stop the cluster and release all the pods of the cluster, but the storage will be reserved
```yaml
# cat examples/orioledb/stop.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orioledb-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orioledb-cluster
  type: Stop

```

```bash
kubectl apply -f examples/orioledb/stop.yaml
```

### [Start](start.yaml)
Start the stopped cluster
```yaml
# cat examples/orioledb/start.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orioledb-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orioledb-cluster
  type: Start

```

```bash
kubectl apply -f examples/orioledb/start.yaml
```

### Expose
Expose a cluster with a new endpoint
#### [Enable](expose-enable.yaml)
```yaml
# cat examples/orioledb/expose-enable.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orioledb-expose-enable
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orioledb-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: orioledb
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`. 
    services:
    - name: internet
      roleSelector: primary
      serviceType: LoadBalancer
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Enable
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Expose

```

```bash
kubectl apply -f examples/orioledb/expose-enable.yaml
```
#### [Disable](expose-disable.yaml)
```yaml
# cat examples/orioledb/expose-disable.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: orioledb-expose-disable
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: orioledb-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: orioledb
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`. 
    services:
    - name: internet
      roleSelector: primary
      serviceType: LoadBalancer
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Disable
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Expose

```

```bash
kubectl apply -f examples/orioledb/expose-disable.yaml
```

### Delete
If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster
```bash
kubectl patch cluster orioledb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster orioledb-cluster

kubectl delete cluster etcdo-cluster
```
