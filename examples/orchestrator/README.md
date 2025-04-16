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
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

Orchestrator cluster has two modes: *raft* and *share-backend*.

- *share-backend*: Orchestrator cluster with shared backend[^1], here we create an ApeCloud MySQL cluster as the backend. Recommended for large scale.

```bash
kubectl apply -f examples/orchestrator/cluster-shared-backend.yaml
```

- *raft*: Orchestrator cluster with Raft consensus[^2]. Recommended for small to medium scale.

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

#### [Scale-out](scale-out.yaml)

> [!IMPORTANT]
> As per the Orchestrator documentation, the number of Orchestrator instances should be odd to avoid split-brain scenarios.
> Make sure the number of Orchestrator instances is always an odd number after scaling in or out.

To scale out the Orchestrator cluster of Share-Backend Mode

```bash
kubectl apply -f examples/orchestrator/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

To scale in the Orchestrator cluster of Share-Backend Mode

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

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/orchestrator/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/orchestrator/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/orchestrator/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/orchestrator/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/orchestrator/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo orchestrator-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

 kubectl delete cluster -n demoorchestrator-cluster

# or delete all clusters created in this example
# you may use the following command:
# kubectl delete -f examples/orchestrator/cluster-shared-backend.yaml
# kubectl delete -f examples/orchestrator/cluster-raft.yaml
```

### Reference

[^1]: Shared Backend, <https://github.com/openark/orchestrator/blob/master/docs/deployment-shared-backend.md>
[^2]: Raft, <https://github.com/openark/orchestrator/blob/master/docs/deployment-raft.md>
