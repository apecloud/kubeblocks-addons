# PolarDB-X

PolarDB-X is a cloud native distributed SQL Database designed for high concurrency, massive storage, complex querying scenarios.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes (cn, cdc)          | Yes                   | Yes              | Yes       | Yes        | No       | Yes    | No      |

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
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

> [!IMPORTANT]
> Make sure the `clusterName` and `namespace` are short such that the length of following string is less than 64 characters
>
> - `<clusterName>`-gms-`<id>`.`<clusterName>`-gms-headless.`<namesapce>`.svc.cluster.local:11306
>
> This is a constraint of the PolarDB-X database. The column `IP_PORT` defined in table `information_schema.ALISQL_CLUSTER_GLOBAL` is of type `VARCHAR(64)`.
> You may login to the database and run the following SQL to check the definition of the table:
>
> ```sql
> show create table information_schema.ALISQL_CLUSTER_GLOBAL;
> ```

Create a polardbx cluster with four components: cn, dn, cdc, and gms.

```bash
kubectl apply -f examples/polardbx/cluster.yaml
```

As PolarDB-X is a distributed database with multiple components. You may prefer to distribute replicas to different nodes to avoid single point of failure. Here is an example of how to distribute replicas to different nodes using `schedulingPolicy` API:

```yaml
kubectl apply -f examples/polardbx/cluster-with-schedule-policy.yaml
```

To connect to the database, you can use the following command to get the connection information:

```bash
kubectl port-forward svc/pxc-cn 3306:3306
mysql -h127.0.0.1 -u$USER_NAME -p$PASSWORD
```

Credentials can be found in the secret `pxc-gms-account-polardbx-root` in the namespace where the cluster is deployed.

```bash
kubectl get secret -n demo pxc-gms-account-polardbx-root -o jsonpath="{.data.password}" | base64 --decode
kubectl get secret -n demo pxc-gms-account-polardbx-root -o jsonpath="{.data.username}" | base64 --decode
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out polardbx cluster by adding ONE more `cn` replica:

```bash
kubectl apply -f examples/polardbx/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in polardbx cluster by deleting ONE `cn` replica:

```bash
kubectl apply -f examples/polardbx/scale-in.yaml
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```bash
kubectl apply -f examples/polardbx/verticalscale.yaml
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

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```bash
kubectl apply -f examples/polardbx/pod-monitor.yaml
```

##### Access the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard [PolarDB-X Dashboard Overview](https://github.com/apecloud/kubeblocks-addons/blob/main/addons/polardbx/dashboards/polardbx-overview.json) to monitor the cluster.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo pxc -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

 kubectl delete cluster -n demopxc
```
