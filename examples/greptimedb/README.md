# GreptimeDB

An open-source, cloud-native, distributed time-series database with PromQL/SQL/Python supported.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes (datanode)                  | Yes                   | Yes              | Yes       | Yes        | No       | Yes    | N/A     |

### Versions

| Versions |
|----------|
| 0.3.2 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- GreptimeDB Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

Create a greptimedb cluster

```bash
kubectl apply -f examples/greptimedb/cluster.yaml
```

It will create a greptimedb cluster with four components in orders: `etcd`, `metadata`, `datanode` and  `frontent`.
Datanode is mainly responsible for storing the actual data for GreptimeDB. Metadata is responsible for storing metadata information for GreptimeDB. Frontend is responsible for receiving and processing user requests. Etcd is used as the consensus algorithm component for metadata.

#### How to access the GreptimeDB

To connect to the greptimedb cluster, you can use the following command.

1. poforward the frontend service to access the greptimedb cluster

```bash
# for mysql client
kubectl port-forward svc/greptimedb-cluster-frontend 4002:4002
# for postgresql client
kubectl port-forward svc/greptimedb-cluster-frontend 4003:4003
```

2. Connect to the greptimedb cluster using the client

```bash
# for mysql client
mysql -h 127.0.0.1 -P 4002
# for postgresql client
psql -h 127.0.0.1 -p 4003
```

To visit the dashboard of greptimedb, you can use the following command.

```bash
kubectl port-forward svc/greptimedb-cluster-frontend 4000:4000
```

Then visit the dashboard at `http://localhost:4000/dashboard`.

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out greptimedb cluster by adding ONE more datanode replica:

```bash
kubectl apply -f examples/greptimedb/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in greptimedb cluster by deleting ONE datanode replica:

```bash
kubectl apply -f examples/greptimedb/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  clusterDef: greptimedb
  componentSpecs:
  - componentDef: greptimedb-datanode-1.0.0
    name: datanode
    replicas: 4 # update replicas as needed
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 500m
        memory: 512Mi
    serviceVersion: 0.3.2
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/greptimedb/verticalscale.yaml
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
kubectl apply -f examples/greptimedb/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/greptimedb/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/greptimedb/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/greptimedb/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo greptimedb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

 kubectl delete cluster -n demogreptimedb-cluster
```
