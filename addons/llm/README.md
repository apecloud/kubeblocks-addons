# LLM

LLM is a fast and easy-to-use library for LLM inference and serving

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- LLM Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create
Create a llm cluster with specified cluster definition
```yaml
# cat examples/llm/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: llm-cluster
  namespace: demo
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

### Restart
Restart the specified components in the cluster
```yaml
# cat examples/llm/restart.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: llm-restart
  namespace: demo
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

### Stop
Stop the cluster and release all the pods of the cluster, but the storage will be reserved
```yaml
# cat examples/llm/stop.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: llm-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: llm-cluster
  type: Stop

```

```bash
kubectl apply -f examples/llm/stop.yaml
```

### Start
Start the stopped cluster
```yaml
# cat examples/llm/start.yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: llm-start
  namespace: demo
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
kubectl patch cluster -n demo llm-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo llm-cluster
```
