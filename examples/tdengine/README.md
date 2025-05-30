# TDengine

TDengine™ is a next generation data historian purpose-built for Industry 4.0 and Industrial IoT. It enables real-time data ingestion, storage, analysis, and distribution of petabytes per day, generated by billions of sensors and data collectors.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes (Scale-out)        | Yes                   | Yes               | Yes       | Yes        | No       | Yes    | N/A   |

### Versions

| Versions |
|----------|
| 3.0.5.0    |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- TDengine™ Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

Create a tdengine cluster:

```bash
kubectl apply -f examples/tdengine/cluster.yaml
```

When the cluster status is `Running`, you can access the TDengine service by login to the pod and show the dnodes

```bash
kubectl exec -i -t tdengine-cluster-tdengine-0 -- taos -s "show dnodes"
```

You will see there are 3 dnodes in the cluster as we defined in the cluster.yaml

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out by adding ONE more replica:

```bash
kubectl apply -f examples/tdengine/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

> [!WARNING]
> This operation is not fully supported by TDEngine.
> Even though you can scale-in through API, it is not recommended to scale-in the cluster, as per documentation of TDEngine.[^1]

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: tdengine
      replicas: 1 # Set the number of replicas to your desired number
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/tdengine/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/tdengine/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/tdengine/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/tdengine/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/tdengine/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo tdengine-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo tdengine-cluster
```

## References

[^1]: Deploy TDengine on K8s using Helm, <https://taosdata.github.io/TDengine-Operator/zh/2.2-tdengine-with-helm.html>
