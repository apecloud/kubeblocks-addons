# Zookeeper

Apache Zookeeper is a centralized service for maintaining configuration information, naming, providing distributed synchronization, and providing group services.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | No      |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Full Backup | zoocreeper | uses `zoocreeper` tool to create a backup |

### Versions

| Versions |
|----------|
| 3.4.14,3.6.4,3.7.2,3.8.4,3.9.2 |

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

Create a zookeeper cluster with three replicas, one leader replica and two follower replicas:

```bash
kubectl apply -f examples/zookeeper/cluster.yaml
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out cluster by adding ONE more `OBSERVER` replica:

```bash
kubectl apply -f examples/zookeeper/scale-out.yaml
```

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe -n demo ops zk-scale-out
```

> [!WARNING]
> As defined, Zookeeper Cluster will be restarted on horizontal scaling. To make sure all config are loaded properly.

After scaling, cluster server list in Zookeeper configuration file `zoo.cfg` will be updated :

```text
# cluster server list
server.0 = zookeeper-cluster-zookeeper-0.zookeeper-cluster-zookeeper-headless.default.svc.cluster.local:2888:3888:participant
server.1
    = zookeeper-cluster-zookeeper-1.zookeeper-cluster-zookeeper-headless.default.svc.cluster.local:2888:3888:participant
server.2
    = zookeeper-cluster-zookeeper-2.zookeeper-cluster-zookeeper-headless.default.svc.cluster.local:2888:3888:participant
server.3
    = zookeeper-cluster-zookeeper-3.zookeeper-cluster-zookeeper-headless.default.svc.cluster.local:2888:3888:observer
```

Information for `server.3` is added on scaling out.

#### [Scale-in](scale-in.yaml)

Horizontal scaling in cluster by deleting ONE replica:

```bash
kubectl apply -f examples/zookeeper/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
      replicas: 3 # Update `replicas` to 1 for scaling in, and to 3 for scaling out
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/zookeeper/verticalscale.yaml
```

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
      replicas: 3
      resources:
        requests:
          cpu: "1"       # Update the resources to your need.
          memory: "2Gi"  # Update the resources to your need.
        limits:
          cpu: "2"       # Update the resources to your need.
          memory: "4Gi"  # Update the resources to your need.
```

### [Expand volume](volumeexpand.yaml)

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

To increase size of volume storage with the specified components in the cluster

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/zookeeper/volumeexpand.yaml
```

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
      replicas: 3
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                # specify new size, and make sure it is larger than the current size
                storage: 30Gi
      volumeClaimTemplates:
        - name: snapshot-log
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                # specify new size, and make sure it is larger than the current size
                storage: 20Gi
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/zookeeper/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```bash
kubectl apply -f examples/zookeeper/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
      stop: true  # set stop `true` to stop the component
      replicas: 3
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/zookeeper/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 3
```

### [Reconfigure](configure.yaml)

Configure parameters with the specified components in the cluster:

```bash
kubectl apply -f examples/zookeeper/configure.yaml
```

`syncLimit` is a configuration parameter that defines the maximum number of ticks a Zookeeper follower can lag behind the leader before it's considered out of sync and must resync with the leader.

In this example updates `syncLimit` to `10` (default to `5` ticks). Increase it for slower networks or larger clusters, and decrease for tighter consistency requirements. Its common range: 2-10 ticks.

To verify the changes, you may log into an Zookeeper instance to check the configuration changes:

```bash
# 2181 is the clientPort
echo "conf" | nc localhost 2181
```

### [Backup](backup.yaml)

> [!NOTE]
> Before you start, please create a `BackupRepo` to store the backup data. Refer to [BackupRepo](../docs/create-backuprepo.md) for more details.

The method `zoocreeper` uses `zoocreeper` tool to create a compressed backup. You may create a backup using:

```bash
kubectl apply -f examples/zookeeper/backup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -n demo -l app.kubernetes.io/instance=zookeeper-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

### [Restore](restore.yaml)

To restore a new cluster from a Backup:

```bash
kubectl apply -f examples/zookeeper/restore.yaml
```

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

##### Step 1. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```bash
kubectl apply -f examples/zookeeper/pod-monitor.yaml
```

It sets path to `/metrics` and port to `metrics` (for container port `7000`).

```yaml
  - path: /metrics
    port: metrics
    scheme: http
```

##### Step 2. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard, e.g. using etcd dashboard from [Grafana](https://grafana.com/grafana/dashboards).

> [!Note]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo zookeeper-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

 kubectl delete cluster -n demozookeeper-cluster
```
