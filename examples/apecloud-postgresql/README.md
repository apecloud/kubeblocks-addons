# Apecloud-postgresql

ApeCloud PostgreSQL is a database that is compatible with PostgreSQL syntax and achieves high availability
through the utilization of the RAFT consensus protocol.

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Apecloud PostgreSQL Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

Create a apecloud-postgresql cluster with specified cluster definition

```bash
kubectl apply -f examples/apecloud-postgresql/cluster.yaml
```

### [Horizontal scaling](horizontalscale.yaml)

Horizontal scaling out or in specified components replicas in the cluster

```bash
kubectl apply -f examples/apecloud-postgresql/horizontalscale.yaml
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/apecloud-postgresql/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/apecloud-postgresql/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/apecloud-postgresql/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/apecloud-postgresql/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/apecloud-postgresql/start.yaml
```

### [Switchover](switchover.yaml)

Switchover a specified instance as the new primary or leader of the cluster

```bash
kubectl apply -f examples/apecloud-postgresql/switchover.yaml
```

### Expose

Expose a cluster with a new endpoint

#### [Enable](expose-enable.yaml)

```bash
kubectl apply -f examples/apecloud-postgresql/expose-enable.yaml
```

#### [Disable](expose-disable.yaml)

```bash
kubectl apply -f examples/apecloud-postgresql/expose-disable.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo ac-postgresql-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo ac-postgresql-cluster
```
