# ClickHouse

ClickHouse is an open-source column-oriented OLAP database management system. Use it to boost your database performance while providing linear scalability and hardware efficiency.

There are two key components in the ClickHouse cluster:

- ClickHouse Server: The ClickHouse server is responsible for processing queries and managing data storage.
- ClickHouse Keeper: The ClickHouse Keeper is responsible for monitoring the health of the ClickHouse server and performing failover operations when necessary, alternative to the Zookeeper.

## Features In KubeBlocks

### Lifecycle Management

#### ClickHouse Server

| Topology           | Horizontal scaling | Vertical scaling | Expand volume | Restart | Stop/Start | Configure | Expose | Switchover |
| ------------------ | ------------------ | ---------------- | ------------- | ------- | ---------- | --------- | ------ | ---------- |
| standalone/cluster | Yes                | Yes              | Yes           | Yes     | Yes        | Yes       | No     | N/A        |

#### ClickHouse Keeper

| Topology | Horizontal scaling | Vertical scaling | Expand volume | Restart | Stop/Start | Configure | Expose | Switchover |
| -------- | ------------------ | ---------------- | ------------- | ------- | ---------- | --------- | ------ | ---------- |
| cluster  | Yes                | Yes              | Yes           | Yes     | Yes        | Yes       | No     | Yes        |

### Versions

| Major Versions | Description |
| -------------- | ----------- |
| 22             | 22.9.4      |
| 24             | 24.8.3      |
| 25             | 25.4.4      |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- ClickHouse Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

#### Standalone Mode

Create a ClickHouse cluster with only ClickHouse server:

```bash
kubectl apply -f examples/clickhouse/cluster-standalone.yaml
```

It will create only one ClickHouse server pod with the default configuration.

To connect to the ClickHouse server, you can use the following command:

```bash
clickhouse-client --host <clickhouse-endpoint> --port 9000 --user admin --password
```

> [!NOTE]
> You may find the password in the secret `<clusterName>-clickhouse-account-admin`.

e.g. you can get the password by the following command:

```bash
kubectl get secrets clickhouse-cluster-clickhouse-account-admin -n demo -oyaml  | yq .data.password -r | base64 -d
```

where `clickhouse-cluster-clickhouse-account-admin` is the secret name, it is named after pattern `<clusterName>-<componentName>-account-<accountName>`, and `password` is the key of the secret.

#### Cluster Mode

Create a ClickHouse cluster with ClickHouse servers and ch-keeper:

```bash
kubectl apply -f examples/clickhouse/cluster.yaml
```

This example shows the way to override the default accounts' password.

Option 1. override the rule `passwordCofnig` to generate password

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: ch-keeper
      replicas: 1
      # Overrides system accounts defined in referenced ComponentDefinition.
      systemAccounts:
        - name: admin # name of the system account
          passwordConfig: # config rule to generate  password
            length: 10
            numDigits: 5
            numSymbols: 0
            letterCase: MixedCases
            seed: clickhouse-cluster
```

Option 2. specify the secret for the account

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: clickhouse
      replicas: 2
      # Overrides system accounts defined in referenced ComponentDefinition.
      systemAccounts:
        - name: admin # name of the system account
          secretRef:
            name: udf-account-info
            namespace: demo
```

Make sure the secret `udf-account-info` exists in the same namespace as the cluster, and has the following data:

```yaml
apiVersion: v1
data:
  password: <SOME_PASSWORD>  # password: required
metadata:
  name: udf-account-info
type: Opaque
```

#### Cluster Mode with TLS Enabled

To create one ClickHouse server pod with the default configuration and TLS enabled.

```bash
kubectl apply -f examples/clickhouse/cluster-tls.yaml
```

Compared to the default configuration, the only difference is the `tls` and `issuer` fields in the `cluster-tls.yaml` file.

```yaml
tls: true  # enable tls
issuer:    # set issuer information
  name: KubeBlocks
```

To connect to the ClickHouse server, you can use the following command:

```bash
clickhouse-client --host <clickhouse-endpoint>  --port 9440 --secure  --user admin --password
```

#### Cluster with Multiple Shards

> [!WARNING]
> The sharding mode is an experimental feature at the moment.

Create a ClickHouse cluster with ch-keeper and clickhouse servers with multiple shards:

```bash
kubectl apply -f examples/clickhouse/cluster-sharding.yaml
```

This example creates a clickhouse cluster with 2 shards, each shard has 2 replicas.

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out Clickhouse by adding ONE more replica:

```bash
kubectl apply -f examples/clickhouse/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in Clickhouse by deleting ONE replica:

```bash
kubectl apply -f examples/clickhouse/scale-in.yaml
```

#### [Keeper-Scale-out](keeper-scale-out.yaml)

Horizontal scaling out Clickhouse Keeper by adding TWO more replica:

```bash
kubectl apply -f examples/clickhouse/keeper-scale-out.yaml
```

#### [Keeper-Scale-in](keeper-scale-in.yaml)

Horizontal scaling in Clickhouse Keeper by deleting TWO replica:

```bash
kubectl apply -f examples/clickhouse/keeper-scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: clickhouse
      replicas: 2 # Update `replicas` to 1 for scaling in, and to 3 for scaling out
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/clickhouse/verticalscale.yaml
```

### Switchover for Clickhouse Keeper

#### Switchover without preferred candidates

Switchover a specified instance as the new primary or leader of the cluster

```yaml
# cat examples/clickhouse/keeper-switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: keeper-switchover
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: ch-keeper
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: "clickhouse-cluster-ch-keeper-0"

```

```bash
kubectl apply -f examples/clickhouse/keeper-switchover.yaml
```

#### Switchover-specified-instance

Switchover a specified instance as the new primary or leader of the cluster

```yaml
# cat examples/clickhouse/keeper-switchover-specified-instance.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: keeper-switchover
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: ch-keeper
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: "clickhouse-cluster-ch-keeper-0"
    # Specifies the instance that will become the new leader, if not specify, the first non leader instance will become candidate.
    # Need to ensure the candidate instance is catch up logs of the quorum, otherwise the switchover will transfer the leader to other instance.
    candidateName: "clickhouse-cluster-ch-keeper-1"

```

```bash
kubectl apply -f examples/clickhouse/keeper-switchover-specified-instance.yaml
```

You may need to update the `opsrequest.spec.switchover.instanceName` field to your desired instance name.

### [Expand volume](volumeexpand.yaml)

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/clickhouse/volumeexpand.yaml
```

### [Reconfigure](configure.yaml)

Reconfigure parameters with the specified components in the cluster

```bash
kubectl apply -f examples/clickhouse/configure.yaml
```

This example will change the `max_bytes_to_read` to `200000000000`.
To verify the configuration, you can connect to the ClickHouse server and run the following command:

```bash
# connect to the clickhouse pod
kubectl exec -it clickhouse-cluster-clickhouse-0 -- /bin/bash
```

and check the configuration:

```bash
# connect to the clickhouse server
clickhouse-client --user $CLICKHOUSE_ADMIN_USER --password $CLICKHOUSE_ADMIN_PASSWORD
> set profile='web';
> select name,value from system.settings where name like 'max_bytes%';
```

<details>
<summary>Explanation of the configuration</summary>
The `user.xml` file is an xml file that contains the configuration of the ClickHouse server.
```xml
<clickhouse>
  <profiles>
    <default>
      <!-- The maximum number of threads when running a single query. -->
      <max_threads>8</max_threads>
    </default>
    <web>
      <max_rows_to_read>1000000000</max_rows_to_read>
      <max_bytes_to_read>100000000000</max_bytes_to_read>
    </web>
  </profiles>
</clickhouse>
```

When updating the configuration, the key we set in the `configure.yaml` file should be the same as the key in the `user.xml` file, for example:

```yaml
# snippet of configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
spec:
  reconfigures:
  - componentName: clickhouse
    parameters:
    - key: clickhouse.profiles.web.max_bytes_to_read
      value: '200000000000'
```

To update parameter `max_bytes_to_read`, we use the full path `clickhouse.profiles.web.max_bytes_to_read` w.r.t the `user.xml` file.

</details>

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/clickhouse/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/clickhouse/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/clickhouse/start.yaml
```

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```bash
kubectl apply -f examples/clickhouse/pod-monitor.yaml
```

It sets endpoints as follows:

```yaml
  podMetricsEndpoints:
    - path: /metrics
      port: http-metrics
      scheme: http
```

> [!NOTE]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo clickhouse-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo  clickhouse-cluster

# delete secret udf-account-info if exists
# kubectl delete secret udf-account-info
```
