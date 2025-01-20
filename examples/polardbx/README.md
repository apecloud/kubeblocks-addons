# PolarDB-X

PolarDB-X is a cloud native distributed SQL Database designed for high concurrency, massive storage, complex querying scenarios.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes (cn)               | Yes                   | Yes              | Yes       | Yes        | No       | Yes    | No      |

### Versions

| Versions |
|----------|
| 2.3.0 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- PolarDB-X Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### [Create](cluster.yaml)

Create a polardbx cluster

```bash
kubectl apply -f examples/polardbx/cluster.yaml
```

As PolarDB-X is a distributed database with multiple components. You may prefer to distribute replicas to different nodes to avoid single point of failure. Here is an example of how to distribute replicas to different nodes using `schedulingPolicy` API:

```yaml
kubectl apply -f examples/polardbx/cluster-with-schedule-policy.yaml
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out polardbx cluster by adding ONE more cn replica:

```bash
kubectl apply -f examples/polardbx/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in polardbx cluster by deleting ONE cn replica:

```bash
kubectl apply -f examples/polardbx/scale-in.yaml
```

### [Expand volume](volumeexpand.yaml)

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created. It is introduced in Kubernetes v1.11 and goes GA in Kubernetes v1.24. It allows Kubernetes users to simply edit their PersistentVolumeClaim objects  without requiring any downtime at all if possible.

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

To increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/polardbx/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/polardbx/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/polardbx/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/polardbx/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster polardbx-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster polardbx-cluster
```
