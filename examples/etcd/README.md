# etcd

etcd is a distributed, highly available key-value store designed to securely store data across a cluster of machines. It provides strong consistency guarantees, ensuring that data is reliably replicated and synchronized among all nodes. etcd is commonly used for configuration management, service discovery, and coordinating distributed systems. Its simplicity and robustness make it a critical component in cloud-native environments, particularly within Kubernetes for maintaining cluster state and configuration.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | Yes      |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Full Backup | datafile | using `etcdcl snapshot save` to create snapshot of the etcd cluster's data |

### Versions

| Major Versions | Description |
|---------------|-------------|
| 3.5.x         | 3.5.6,3.5.15|

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

## Examples

### [Create](cluster.yaml)

Create an etcd cluster with three replicas, one leader and two followers.

```bash
kubectl apply -f examples/etcd/cluster.yaml
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out ETCD cluster by adding ONE more replica:

```bash
kubectl apply -f examples/etcd/scale-out.yaml
```

After applying the operation, you will see a new pod created and the cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `follower`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe ops etcd-scale-out
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in etcd cluster by deleting ONE replica:

```bash
kubectl apply -f examples/etcd/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: etcd-cluster
  namespace: default
spec:
  componentSpecs:
    - name: etcd
      replicas: 3 # Update `replicas` to 1 for scaling in, and to 3 for scaling out
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```bash
kubectl apply -f examples/etcd/verticalscale.yaml
```

You will observe that the `follower` pod is recreated first, followed by the `leader` pod, to ensure the availability of the cluster.

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: etcd-cluster
  namespace: default
spec:
  componentSpecs:
    - name: etcd
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

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created. It is introduced in Kubernetes v1.11 and goes GA in Kubernetes v1.24. It allows Kubernetes users to simply edit their PersistentVolumeClaim objects  without requiring any downtime at all if possible[^4].

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

To increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/etcd/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=etcd-cluster -n default
```

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: etcd-cluster
  namespace: default
spec:
  componentSpecs:
    - name: etcd
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: "<you-preferred-sc>"
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 30Gi  # specify new size, and make sure it is larger than the current size
```

### [Restart](restart.yaml)

Restart the specified components in the cluster, and instances will be recreated on after another to ensure the availability of the cluster

```bash
kubectl apply -f examples/etcd/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```bash
kubectl apply -f examples/etcd/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: etcd-cluster
  namespace: default
spec:
  componentSpecs:
    - name: etcd
      stop: true  # set stop `true` to stop the component
      replicas: 2
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/etcd/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: etcd-cluster
  namespace: default
spec:
  componentSpecs:
    - name: etcd
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 2
```

### Switchover(switchover.yaml)

A switchover in database clusters is a planned operation that transfers the primary (leader) role from one database instance to another. The goal of a switchover is to ensure that the database cluster remains available and operational during the transition.

To perform a switchover, you can apply the following yaml file:

```bash
kubectl apply -f examples/etcd/switchover.yaml
```

### [Backup](backup.yaml)

You may find the list of supported Backup Methods:

```bash
# etcd-cluster-etcd-backup-policy is the backup policy name
kubectl get bp etcd-cluster-etcd-backup-policy -oyaml | yq '.spec.backupMethods[].name'
```

The method `datafile` uses `etcdctl snapsho save` to do a full backup. You may create a backup using:

```bash
kubectl apply -f examples/etcd/backup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -l app.kubernetes.io/instance=etcd-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

### [Restore](restore.yaml)

To restore a new cluster from a Backup:

```bash
kubectl apply -f examples/etcd/restore.yaml
```

### Observability

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

##### Step 1. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```bash
kubectl apply -f examples/etcd/pod-monitor.yaml
```

It sets path to `/metrics` and port to `client` (for container port `2379`).

```yaml
  - path: /metrics
    port: client
    scheme: http
```

##### Step 2. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard, e.g. using etcd dashboard from [grafana](https://grafana.com/grafana/dashboards) .

> [!Note]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster etcd-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster etcd-cluster
```

