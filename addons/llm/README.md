# LLM

LLM is a fast and easy-to-use library for LLM inference and serving

## Prerequisites

This example assumes that you have a Kubernetes cluster installed and running, and that you have installed the kubectl command line tool and helm somewhere in your path. Please see the [getting started](https://kubernetes.io/docs/setup/)  and [Installing Helm](https://helm.sh/docs/intro/install/) for installation instructions for your platform.

Also, this example requires kubeblocks installed and running. Here is the steps to install kubeblocks, please replace "`$kb_version`" with the version you want to use.
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
Enable llm
```yaml
# cat examples/llm/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: llm-cluster
  namespace: default
spec:
  # Specifies the name of the ClusterDefinition to use when creating a Cluster.
  clusterDefinitionRef: vllm
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
  - name: vllm
    componentDef: vllm
    replicas: 1
    resources:
      limits:
        cpu: '2'
        memory: 4Gi
      requests:
        cpu: '2'
        memory: 4Gi
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
kubectl apply -f examples/llm/cluster.yaml
```

### [Restart](restart.yaml)
Restart the specified components in the cluster
```yaml
# cat examples/llm/restart.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: llm-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: llm-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: vllm

```

```bash
kubectl apply -f examples/llm/restart.yaml
```

### [Stop](stop.yaml)
Stop the cluster and release all the pods of the cluster, but the storage will be reserved
```yaml
# cat examples/llm/stop.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: llm-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: llm-cluster
  type: Stop

```

```bash
kubectl apply -f examples/llm/stop.yaml
```

### [Start](start.yaml)
Start the stopped cluster
```yaml
# cat examples/llm/start.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: llm-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: llm-cluster
  type: Start

```

```bash
kubectl apply -f examples/llm/start.yaml
```

### Delete
If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster
```bash
kubectl patch cluster llm-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster llm-cluster
```
