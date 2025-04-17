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
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

Create a mariadb cluster with ONE replica:

```bash
kubectl apply -f examples/mariadb/cluster.yaml
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/mariadb/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/mariadb/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/mariadb/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/mariadb/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/mariadb/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo mariadb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo mariadb-cluster
```
