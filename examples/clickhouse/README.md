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
| standalone/cluster | Yes                | Yes              | Yes           | Yes     | Yes        | Yes       | Yes    | N/A        |

#### ClickHouse Keeper

| Topology | Horizontal scaling | Vertical scaling | Expand volume | Restart | Stop/Start | Configure | Expose | Switchover |
| -------- | ------------------ | ---------------- | ------------- | ------- | ---------- | --------- | ------ | ---------- |
| cluster  | Yes                | Yes              | Yes           | Yes     | Yes        | Yes       | N/A    | Yes        |

### Backup and Restore

| Feature            | Method            | Description                                                                           |
| ------------------ | ----------------- | ------------------------------------------------------------------------------------- |
| Full Backup        | clickhouse-backup | uses `clickhouse-backup` tool to perform full backups of ClickHouse data              |
| Incremental Backup | clickhouse-backup | uses `clickhouse-backup` tool to perform incremental backups based on previous backup |


### Versions

| Major Versions | Description               |
| -------------- | ------------------------- |
| 22             | 22.3.18, 22.3.20, 22.8.21 |
| 24             | 24.8.3                    |
| 25             | 25.4.4, 25.9.7            |

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

It will create only one ClickHouse server pod with the default configuration. This example includes a predefined secret `udf-account-info` with password `password123`.

To connect to the ClickHouse server, you can use the following command:

```bash
clickhouse-client --host <clickhouse-endpoint> --port 9000 --user admin --password
```

> [!NOTE]
> The password is defined in the secret `udf-account-info` or you can find it in secrets matching pattern `<clusterName>-*-account-admin`.

e.g. you can get the password by the following command:

```bash
# Get the secret name for standalone cluster
SECRET_NAME=$(kubectl get secrets -n demo -o name | grep clickhouse-standalone | grep account-admin)

# Get username and password
kubectl get $SECRET_NAME -n demo -o jsonpath='{.data.username}' | base64 -d && echo
kubectl get $SECRET_NAME -n demo -o jsonpath='{.data.password}' | base64 -d && echo

# Or from the predefined secret (if used)
kubectl get secrets udf-account-info -n demo -o jsonpath='{.data.password}' | base64 -d && echo
```

#### Cluster Mode

Create a ClickHouse cluster with ClickHouse servers and ch-keeper. The default cluster configuration includes sharding with 2 shards, each shard having 2 replicas:

```bash
kubectl apply -f examples/clickhouse/cluster.yaml
```

This example creates a cluster with:
- 1 ClickHouse Keeper instance for coordination (`ch-keeper` component using `clickhouse-keeper-1` ComponentDef)
- 2 shards with 2 replicas each (total 4 ClickHouse server instances using `clickhouse-1` ComponentDef)
- Shows how to override the default accounts' password using a predefined secret

Option 1. override the rule `passwordConfig` to generate password

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
    - name: ch-keeper
      replicas: 1
      # Overrides system accounts defined in referenced ComponentDefinition.
      systemAccounts:
        - name: admin # name of the system account
          secretRef:
            name: udf-account-info
            namespace: demo
  shardings:
    - name: clickhouse
      shards: 2
      template:
        name: clickhouse
        replicas: 2
        systemAccounts:
          - name: admin
            secretRef:
              name: udf-account-info
              namespace: demo
```

The secret `udf-account-info` is automatically created with the cluster and contains:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: udf-account-info
  namespace: demo
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=  # 'password123' in base64
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


### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out Clickhouse by adding ONE more replica:

```bash
kubectl apply -f examples/clickhouse/scale-out.yaml
```

#### [Scale-out Sharding](scale-out-sharding.yaml)

Horizontal scaling out ClickHouse by adding ONE more shard (from 2 shards to 3 shards):

```bash
kubectl apply -f examples/clickhouse/scale-out-sharding.yaml
```

This operation increases the number of shards in the ClickHouse cluster, which provides better data distribution and query performance for large datasets.

> [!IMPORTANT]
> **Post Scale-out Processing Required**: After scaling out shards, you need to copy database and table schemas to new shards using the post-processing operation:
>
> ```bash
> kubectl apply -f examples/clickhouse/post-scale-out-shard.yaml
> ```
>
> This operation copies all existing database schemas and table structures from old shards to the new shards.

#### [Scale-in](scale-in.yaml)

Horizontal scaling in Clickhouse by deleting ONE replica:

```bash
kubectl apply -f examples/clickhouse/scale-in.yaml
```

#### [Scale-in Sharding](scale-in-sharding.yaml)

Horizontal scaling in ClickHouse by removing ONE shard (from 3 shards back to 2 shards):

```bash
kubectl apply -f examples/clickhouse/scale-in-sharding.yaml
```

> [!WARNING]
> Scaling in shards will permanently remove data from the removed shards. Make sure to backup or redistribute data before scaling in.

#### [Post Scale-out Shard Processing](post-scale-out-shard.yaml)

Copy database and table schemas to new shards after shard scale-out:

```bash
kubectl apply -f examples/clickhouse/post-scale-out-shard.yaml
```

This operation should be run after scaling out shards to ensure new shards have the same database schemas and table structures as existing shards.

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

Alternatively, you can update the `replicas` field in the `spec.shardings[].template.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  shardings:
    - name: clickhouse
      shards: 2
      template:
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

> [!NOTE]
> This reconfigure section is applicable for ClickHouse Addons v1.0.1.
> Those who are using ClickHouse Addons v1.0.2 and above, please refer to [Using Config Templates](../addons/clickhouse/README.md#using-config-templates) for more details.


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


### Using Config Templates

> [!NOTE]
> Applicable for ClickHouse Addons v1.0.2+.

Create a cluster that uses a custom configuration template (`user.xml` settings):

```bash
kubectl apply -f examples/clickhouse/cluster-with-config-templates.yaml
```

This example will create a ClickHouse cluster with user customized config templates, which is defined in the ConfigMap named `custom-user-configuration-tpl` in the namespace `demo`, through the `configs` API showing below:

```yaml
configs:
  - name: clickhouse-user-tpl # refers to the config name defined in `componentDefinition.spec.configs[].name'
    configMap:
      name: custom-user-configuration-tpl # refers to your configmap with customized configuration.
```

To verify the configuration, you can connect to the ClickHouse server and run the following command:

```bash
clickhouse-client --user $CLICKHOUSE_ADMIN_USER --password $CLICKHOUSE_ADMIN_PASSWORD
```

and check the configuration:

```bash
> set profile='default'; # set the profile to `default`
> select name,value from system.settings where name like 'max_threads%'; # check the `max_threads` configuration, which is `8` by default.
```

There are two ways to update the configuration:

#### Option 1. Update through Variables

- Step 1. Define a variable in the Config Template:

    For example, in the ConfigMap `custom-user-configuration-tpl`, we defined a variable `udf_max_threads`  and how it will be used in the `user.xml` file:

    ```yaml
    data:
      user.xml: |
        {{- $var_max_threads := "8" }}      # default value is `8`
        {{- if index . "udf_max_threads" }} # if the variable is defined, use the value of the variable
        {{- $var_max_threads = $.udf_max_threads }} # use the value of the variable
        {{- end }}

        <clickhouse>
          <profiles>
            <default>
              <max_threads>{{ $var_max_threads }}</max_threads>
        # ... other configurations omitted for brevity ...
    ```

- Step 2. Specify the variable and its value in the `cluster-with-config-templates.yaml` CR:

    ```yaml
    configs:
    - name: clickhouse-user-tpl
      configMap:
        name: custom-user-configuration-tpl
      variables:
        udf_max_threads: "16" # set variable `udf_max_threads` to 16.
    ```

    Login to the ClickHouse server and check the configuration:
    ```bash
    clickhouse-client --user $CLICKHOUSE_ADMIN_USER --password $CLICKHOUSE_ADMIN_PASSWORD
    > set profile='default';
    > select name,value from system.settings where name like 'max_threads%';
    ```

    You will see the `max_threads` configuration is `16`.

#### Option 2. Update through config template

- Step 1. Update Config Template

    For example, in the ConfigMap `custom-user-configuration-tpl`, you can update the `user.xml` file directly:

    ```yaml
    data:
      user.xml: |
        <clickhouse>
          <profiles>
            <default>
              <max_threads>16</max_threads>  # change from 8 to 16.
        # ... other configurations omitted for brevity ...
    ```

- Step 2. Annotate Component to trigger a reconcile

    Updates in ConfigMap will not trigger a reconcile of the cluster, you need to annotate the component to trigger a reconcile.

    For example, if the component name is `clickhouse-cluster-clickhouse`, you can run the following command:
    ```bash
    kubectl annotate component clickhouse-cluster-clickhouse kubeblocks.io/config=max_threads -n demo
    ```

#### Comparison between Option 1 and Option 2

| Aspect                   | Option 1 (Variables)                                    | Option 2 (Config Template)                            |
| ------------------------ | ------------------------------------------------------- | ----------------------------------------------------- |
| **Configuration Method** | Through variables in cluster CR                         | Direct modification of config template                |
| **Reconcile Trigger**    | Automatic when CR is updated                            | Manual annotation required                            |
| **Complexity**           | Lower - declarative approach                            | Higher - requires understanding of template structure |
| **Use Case**             | When only a couple of configurations need to be updated | Best for batch updates of configurations              |

You can choose the appropriate method based on your needs and operational preferences.

### Backup and Restore

- Backups are created per shard.
- Schema and RBAC restore runs once on the first shard and uses `ON CLUSTER INIT_CLUSTER_NAME` to apply DDL across all shards.
- Data is restored from each shard's backup.
- **Important**: Standalone and cluster backups are NOT interchangeable. A backup from standalone can only be restored to standalone, and a cluster backup can only be restored to a cluster with compatible topology.

#### Prerequisites for Backup

1. **Setup BackupRepo**: Update `examples/clickhouse/backuprepo.yaml` with your storage provider config (S3, MinIO, etc.) and apply it:
```bash
kubectl apply -f examples/clickhouse/backuprepo.yaml
```

Make sure to update the following fields in `backuprepo.yaml`:
- `storageProviderRef`: Set to your storage provider (s3, oss, cos, gcs, obs, minio, etc.)
- `config.bucket`: Your storage bucket name
- `config.region`: Your storage region
- `credential.name`: Reference to your storage credentials secret

Create the credentials secret:

```bash
kubectl create secret generic credential-for-backuprepo \
  --from-literal=accessKeyId=<your-access-key> \
  --from-literal=secretAccessKey=<your-secret-key> \
  --namespace=kb-system
```

#### [Create Backup](backup.yaml)

Create a backup of your ClickHouse cluster:

```bash
kubectl apply -f examples/clickhouse/backup.yaml
```

This will create a full backup using the `clickhouse-backup` tool. The backup supports both:
- **Full Backup**: Complete backup of all ClickHouse data
- **Incremental Backup**: Backup only changes since the last backup

To create an incremental backup, modify the `backupMethod` field in `backup.yaml`:

```yaml
spec:
  backupMethod: incremental  # Change from 'full' to 'incremental'
```

#### Restore Settings

> [!NOTE]
> Restoring a TLS-enabled cluster directly from backup is NOT supported. You should restore the cluster with TLS disabled first, and then enable TLS manually after the restore process is complete.

Restore process will restore schema and rbac first, then restore data. You can tune schema-ready waiting behavior for restore jobs via Helm values:

```yaml
restore:
  schemaReadyTimeoutSeconds: 1800
  schemaReadyCheckIntervalSeconds: 5
```

To restore the cluster from a backup, you can apply the restore configuration:

```bash
kubectl apply -f examples/clickhouse/restore.yaml
```
This will create a new cluster named `clickhouse-cluster-restore` with the data restored from the specified backup.
It also creates the necessary system account secret `udf-restore-account-info`.

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

### Expose

Expose ClickHouse services to external access. Note that ClickHouse Keeper does not need to be exposed as it's an internal coordination service.

#### [Expose with LoadBalancer](expose-enable.yaml)

Expose ClickHouse using LoadBalancer service type:

```bash
kubectl apply -f examples/clickhouse/expose-enable.yaml
```

This will create a LoadBalancer service for the ClickHouse component. You can then connect using:

```bash
clickhouse-client --host <loadbalancer-ip> --port 9000 --user admin --password
```

#### [Disable Expose](expose-disable.yaml)

Remove the exposed service:

```bash
kubectl apply -f examples/clickhouse/expose-disable.yaml
```

#### [Cluster with NodePort](cluster-with-nodeport.yaml)

Create a ClickHouse cluster with NodePort services:

```bash
kubectl apply -f examples/clickhouse/cluster-with-nodeport.yaml
```

This example demonstrates two approaches:
1. Cluster-level NodePort service that load balances across all ClickHouse instances
2. Per-pod NodePort services for direct access to individual ClickHouse instances

To connect via NodePort:

```bash
# Get the NodePort
kubectl get svc -n demo | grep clickhouse

# Connect using node IP and NodePort
clickhouse-client --host <node-ip> --port <node-port> --user admin --password
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
# Delete clusters and resources
kubectl delete -f examples/clickhouse/cluster.yaml
kubectl delete -f examples/clickhouse/cluster-standalone.yaml
...
```
