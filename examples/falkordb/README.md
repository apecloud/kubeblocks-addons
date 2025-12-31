# FalkorDB

FalkorDB is an open source (SSPL licensed) in-memory graph database based on Redis. This example shows how it can be managed in Kubernetes with KubeBlocks.

## Features In KubeBlocks

### Lifecycle Management

|   Topology       | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| replication     | Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | Yes      |
| standalone      | Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | N/A      |
| sharding      | Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | Yes      |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Full Backup | datafile  | uses `redis-cli BGSAVE` command to backup data |
| Continuous Backup | aof | continuously perform incremental backups by archiving Append-Only Files (AOF) |

### Versions

| Major Versions | Description |
|---------------|-------------|
| 4.0           | 4.12.5 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- FalkorDB Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

Create a FalkorDB replication cluster with two components, one for FalkorDB, and one for Sentinel[^1].

For optimal reliability, you should run at least three Sentinel replicas. Having three or more Sentinels ensures a quorum can be reached during failover decisions, maintaining the high availability of your FalkorDB deployment.

```bash
kubectl apply -f examples/falkordb/cluster.yaml
```

A cluster named `falkordb-replication` will be created with 1 primary pod, 1 secondary pod, and 3 sentinel pods.

```bash
kubectl get -n demo cluster falkordb-replication # get cluster info
kubectl get pod -n demo -l app.kubernetes.io/instance=falkordb-replication # get all pods of the cluster
```

> [!NOTE]
> If all Pods are running, but the cluster status is still `Creating`, you may need to wait for a while until all FalkorDB Pods are ready with corresponding Roles.

To check the role of each FalkorDB pod, you can use the following command:

```bash
# replace `falkordb-replication` with your cluster name
kubectl get po -n demo -l app.kubernetes.io/instance=falkordb-replication,apps.kubeblocks.io/component-name=falkordb -L kubeblocks.io/role
```

#### Why the Sentinel starts first?

The Sentinel (based on the Redis Sentinel) is a high availability solution for FalkorDB (Redis). It provides monitoring, notifications, and automatic failover for FalkorDB instances.

Each FalkorDB replica, from the FalkorDB component, upon startup, will connect to the Sentinel instances to get the current leader and follower information. It needs to determine:

- Whether it should act as the primary (master) node.
- If not, which node is the current primary to replicate from.

In more detail, each FalkorDB replica will:

1. Check for Existing Primary Node
    - Queries the Sentinel to find out if a primary node is already elected.
    - Retrieve the primary's address and port.
1. Initialize as Primary if Necessary
    - If no primary is found (e.g., during initial cluster setup), it configures the current FalkorDB instance to become the primary.
    - Updates FalkorDB configuration to disable replication.
1. Configure as Replica if Primary Exists
    - If a primary is found, it sets up the current FalkorDB instance as a replica.
    - Updates the FalkorDB configuration with the `replicaof` directive pointing to the primary's address and port.
    - Initiates replication to synchronize data from the primary.

KubeBlocks ensures that the Sentinel starts first to provide the necessary information for the FalkorDB replicas to initialize correctly. Such dependency is well-expressed in the KubeBlocks CRD `ClusterDefinition` ensuring the correct startup order.

More details on how components for the `replication` topology are started, upgraded can be found in:

```bash
kubectl get cd falkordb -oyaml | yq '.spec.topologies[] | select(.name=="replication") | .orders'
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out FalkorDB component by adding ONE more replica:

```bash
kubectl apply -f examples/falkordb/scale-out.yaml
```

After applying the operation, you will see a new pod created and the cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `secondary`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe -n demo ops falkordb-scale-out
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in FalkorDB component by removing ONE replica:

```bash
kubectl apply -f examples/falkordb/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: falkordb
      serviceVersion: "4.12.5"
      replicas: 2 # decrease `replicas` for scaling in, and increase for scaling out
      disableExporter: false
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

Vertical scaling up or down requests and limits cpu or memory resource for FalkorDB component:

```bash
kubectl apply -f examples/falkordb/verticalscale.yaml
```

You will observe that the `follower` pods are recreated first, followed by the `leader` pod, to ensure the availability of the cluster.

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: falkordb
      serviceVersion: "4.12.5"
      replicas: 2 # decrease `replicas` for scaling in, and increase for scaling out
      resources:
        requests:
          cpu: "1"       # Update the resources to your need.
          memory: "2Gi"  # Update the resources to your need.
        limits:
          cpu: "2"       # Update the resources to your need.
          memory: "4Gi"  # Update the resources to your need.
```

### [Expand volume](volumeexpand.yaml)

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created. It is introduced in Kubernetes v1.11 and goes GA in Kubernetes v1.24. It allows Kubernetes users to simply edit their PersistentVolumeClaim objects without requiring any downtime at all if possible.

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

If you don't have a storage class that supports volume expansion, you can create a new one. Please refer to [CSI drivers](https://kubernetes-csi.github.io/docs/drivers.html) for more information.

To increase size of volume storage with the FalkorDB component in the cluster:

```bash
kubectl apply -f examples/falkordb/volumeexpand.yaml
```

Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: falkordb
      serviceVersion: "4.12.5"
      replicas: 2
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

Restart the specified components in the cluster

```bash
kubectl apply -f examples/falkordb/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

To stop the all component (without specifying the component name) in the cluster:

```bash
kubectl apply -f examples/falkordb/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting all `spec.componentSpecs.stop` field to `true`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: falkordb
      serviceVersion: "4.12.5"
      stop: true  # set stop `true` to stop the component
      replicas: 2
      ...
    - name: falkordb-sent
      stop: true  # set stop `true` to stop the component
      replicas: 3
      ....
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/falkordb/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting all `spec.componentSpecs.stop` field to `false`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: falkordb
      serviceVersion: "4.12.5"
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 2
    - name: falkordb-sent
      stop: false  # set stop `true` to stop the component
      replicas: 3
      ....
```

### [Reconfigure](configure.yaml)

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster:

```bash
kubectl apply -f examples/falkordb/configure.yaml
```

This example will change the `maxclients` to `10001` for the FalkorDB component.
`maxclients` in FalkorDB specifies the maximum number of simultaneous client connections the server will accept. Once this limit is reached, FalkorDB will start rejecting new connections until existing clients disconnect.

> [!CAUTION]
> It is defined as a static parameter, which means the FalkorDB component will be restarted after the reconfiguration.

To verify the reconfiguration, you can connect to the FalkorDB pod and check the configuration with the following command:

```bash
falkordb> config get maxclients
```

And the output should be:

```bash
1) "maxclients"
2) "10001"     # where 10001 is the new value set in the reconfiguration
```

### [Backup](backup.yaml)

> [!IMPORTANT]
> Before you start, please create a `BackupRepo` to store the backup data. Refer to [BackupRepo](../docs/create-backuprepo.md) for more details.

You may find the supported backup methods in the `BackupPolicy` of the cluster, e.g. `falkordb-replication-falkordb-backup-policy` in this case, and find how these methods will be scheduled in the `BackupSchedule` of the cluster, e.g.. `falkordb-replication-falkordb-backup-schedule` in this case.

To the the list of backup policies and schedules, you can use the following command:

```bash
kubectl get backuppolicy -n demo falkordb-replication-falkordb-backup-policy -oyaml | yq '.spec.backupMethods[].name'
```

And the output should be like:

```yaml
datafile  # for base backup
aof       # for pitr
volume-snapshot # for snapshot backup, make sure the storage class supports volume snapshot
```

#### [Full Backup](backup.yaml)

To create a backup for the reids component in the cluster:

```bash
kubectl apply -f examples/falkordb/backup.yaml
```

It will trigger a backup operation for the FalkorDB component using `redis-cli BGSAVE` command against one secondary pod.
After the operation, you will see a `Backup` is created

```bash
kubectl get backup -n demo -l app.kubernetes.io/instance=falkordb-replication
```

Information, such as `path`, `timeRange` about the backup will be recorded into the `Backup` resource.

#### Continuous Backup

FalkorDB Append Only Files(AOFs) record every write operation received by the server, in the order they were processed, which allows FalkorDB to reconstruct the dataset by replaying these commands.
KubeBlocks supports continuous backup for the FalkorDB component by archiving Append-Only Files (AOF). It will process incremental AOF files, update base AOF file, purge expired files and save backup status (records metadata about the backup process, such as total size and timestamps, to the `Backup` resource).

To create a continuous backup for the falkordb component, you should follow the steps below:

1. set variable `aof-timestamp-enabled` to `yes`

```bash
kubectl apply -f examples/falkordb/reconfigure-aof.yaml
```

> [!IMPORTANT]
> Once `aof-timestamp-enabled` is on, FalkorDB will include timestamp in the AOF file.
> It may have following side effects: storage overhead, performance overhead (write latency).
> It is not recommended to enable this feature when you have high write throughput, or you have limited storage space.

1. enable continuous backup

update the `BackupSchedule` to enable the `aof` method.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
metadata:
  name: falkordb-replication-falkordb-backup-policy
  namespace: demo
spec:
  backupPolicyName: falkordb-replication-falkordb-backup-policy
  schedules:
  - backupMethod: datafile
    # ┌───────────── minute (0-59)
    # │ ┌───────────── hour (0-23)
    # │ │ ┌───────────── day of month (1-31)
    # │ │ │ ┌───────────── month (1-12)
    # │ │ │ │ ┌───────────── day of week (0-6) (Sunday=0)
    # │ │ │ │ │
    # 0 18 * * *
    # schedule this job every day at 6:00 PM (18:00).
    cronExpression: 0 18 * * * # update the cronExpression to your need
    enabled: false # set to `true` to schedule base backup periodically
    retentionPeriod: 7d # set the retention period to your need
  - backupMethod: aof
    cronExpression: 0 18 * * 0
    enabled: true     # set this to `true` to enable continous backup
    retentionPeriod: 7d
  - backupMethod: volume-snapshot
    cronExpression: 0 18 * * 0
    enabled: false   # set to `true` to schedule base backup using volume snapshot periodically
    retentionPeriod: 7d
```

#### Backup using Cluster API

Alternatively, you may update `spec.backup` field to the desired backup method.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  # Specifies the backup configuration of the Cluster.
  backup:
    cronExpression: 0 18 * * *
    enabled: true     #  Specifies whether automated backup is enabled for the Cluster.
    method: datafile  #  Specifies the backup method to use, as defined in backupPolicy
    pitrEnabled: true #  Specifies whether to enable point-in-time recovery
    retentionPeriod: 7d # set the retention period to your need
    # Specifies the name of the BackupRepo to use for storing backups
    # If not specified, the default BackupRepo will be used.
    # `default` BackupRepo is the one annotated with `dataprotection.kubeblocks.io/is-default-repo=true`
    repoName: kb-oss
  componentSpecs:
    - name: falkordb
      serviceVersion: "4.12.5"
      ...
```

### [Restore](restore.yaml)

To restore a new cluster from a Backup:

```bash
kubectl apply -f examples/falkordb/restore.yaml
```

### Expose

Expose a cluster with a new endpoint

#### [Enable](expose-enable.yaml)

```bash
kubectl apply -f examples/falkordb/expose-enable.yaml
```

#### [Disable](expose-disable.yaml)

```bash
kubectl apply -f examples/falkordb/expose-disable.yaml
```

#### Expose SVC using Cluster API

Alternatively, you may expose service by updating `spec.services`

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  # append service to the list
  services:
    # add annotation for cloud loadbalancer if
    # services.spec.type is LoadBalancer
    # here we use annotation for alibaba cloud for example
  - annotations:
      service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: internet
    componentSelector: falkordb
    name: falkordb-vpc
    serviceName: falkordb-vpc
    # optional. it specify defined role as selector for the service.
    # onece specified, service will select and route traffic to Pods with the label
    # "kubeblocks.io/role=<specified-role-name>".
    # valid options are: [primary, secondary] for MySQL
    roleSelector: primary
    spec:  # defines the behavior of a K8s service.
      ipFamilyPolicy: PreferDualStack
      ports:
      - name: tcp-falkordb
        # port to expose
        port: 6379
        protocol: TCP
        targetPort: falkordb
      # Determines how the Service is exposed. Defaults to 'ClusterIP'.
      # Valid options are [`ClusterIP`, `NodePort`, and `LoadBalancer`]
      type: LoadBalancer
  componentSpecs:
    - name: falkordb
      serviceVersion: "4.12.5"
      ...
```

If the service is of type `LoadBalancer`, please add annotations for cloud loadbalancer depending on the cloud provider you are using. Here list annotations for some cloud providers:

```yaml
# alibaba cloud
service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: "internet"  # or "intranet"

# aws
service.beta.kubernetes.io/aws-load-balancer-type: nlb  # Use Network Load Balancer
service.beta.kubernetes.io/aws-load-balancer-internal: "true"  # or "false" for internet

# azure
service.beta.kubernetes.io/azure-load-balancer-internal: "true" # or "false" for internet

# gcp
networking.gke.io/load-balancer-type: "Internal" # for internal access
cloud.google.com/l4-rbs: "enabled" # for internet
```

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### [Create a Cluster](cluster.yaml)

Create a new cluster with following command:

> [!NOTE]
> Make sure `spec.componentSpecs.disableExporter` is set to `false` when creating cluster.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: falkordb
      serviceVersion: "4.12.5"
      disableExporter: false # set to `false` to enable exporter
```

```bash
kubectl apply -f examples/falkordb/cluster.yaml
```

When the cluster is running, each POD should have a sidecar container, named `metrics` running the postgres-exporter.

#### Create PodMonitor

##### Step 1. Query ScrapePath and ScrapePort

You can retrieve the `scrapePath` and `scrapePort` from pod's exporter container.

```bash
kubectl get po falkordb-replication-falkordb-0 -oyaml | yq '.spec.containers[] | select(.name=="metrics") | .ports'
```

And the expected output is like:

```text
- containerPort: 9121
  name: http-metrics
  protocol: TCP
```

Or you may check the `scrapePath` and `scrapePort` from the headless service of the FalkorDB component.

And the expected output is like:

```text
monitor.kubeblocks.io/path: /metrics
monitor.kubeblocks.io/port: "9121"
monitor.kubeblocks.io/scheme: http
```

Or you may check the `scrapePath` and `scrapePort` from the `ComponentDefinition` of the FalkorDB component.

1. check which container is used for the exporter

```bash
kubectl get cmpd <falkordb-cmpd-name> -oyaml | yq '.spec.exporter'
```

And the expected output is like:

```text
containerName: metrics  # which container for the exporter
scrapePath: /metrics    # scrape path
scrapePort: http-metrics # scrape port
```

##### Step 2. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```bash
kubectl apply -f examples/falkordb/pod-monitor.yaml
```

##### Step 3. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard.

The `redis_exporter` used here is provided by [redis_exporter](https://github.com/oliver006/redis_exporter)[^3], and more dashboards can be found in the Grafana dashboard store[^2].

> [!NOTE]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

Sometimes the default dashboard may not work as expected, you may need to adjust the dashboard to match the labels the metrics are scraped with, in particular, the `job` label. In our case, the `job` variable should be set to `monitoring/falkordb-replication-pod-monitor` in the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster:

```bash
kubectl patch cluster -n demo falkordb-replication -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo falkordb-replication
```

### More Examples to Create a FalkorDB

FalkorDB has various deployment topology, such as standalone, replication, sharding, etc. Here are some examples to create different FalkorDB clusters.

#### Create FalkorDB Replication with NodePort

FalkorDB and Sentinel's advertise port is mainly used for correct node discovery and communication in distributed deployment environments. The advertise port is the port that a FalkorDB or Sentinel node announces to other nodes or clients as its externally accessible service port. This is especially important in containerized, NAT, or port-mapped environments where the actual listening port inside the container may differ from the port exposed to the outside world.

- For FalkorDB, the `cluster-announce-port` configuration allows the node to advertise a different port than the one it listens on. This ensures that other nodes or clients can connect to the correct external port.
- For Sentinel, the `sentinel announce-port` configuration serves a similar purpose, allowing Sentinel nodes to announce the correct external port for inter-node communication and monitoring.

This mechanism solves the problem where the internal and external ports are inconsistent, ensuring reliable communication and failover in FalkorDB and Sentinel clusters.

To access falkordb replication from the outside of K8s cluster, you should create a falkordb replication cluster (with an official FalkorDB Sentinel HA) with `NodePort` service type to advertise addresses.

```bash
kubectl apply -f examples/falkordb/cluster-with-nodeport.yaml
```

This example shows how to create a falkordb replication cluster and override the service type of the `falkordb-advertised` service to `NodePort`.
```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
  - name: falkordb
    services:
    - name: falkordb-advertised  # override service named `falkordb-advertised` defined in ComponentDefinition
      serviceType: NodePort
      podService: true
# irrelevant lines commited
  - name: falkordb-sent
    services:
    - name: sentinel-advertised  # override service named `sentinel-advertised` defined in ComponentDefinition
      serviceType: NodePort
      podService: true
# irrelevant lines commited
```
Service `falkordb-advertised` and `falkordb-sent` are defined in `ComponentDefinition` name `falkordb-4` and `falkordb-sent-4`.  They are used to to parse the advertised endpoints of the FalkorDB pods and Sentinel Pods.

#### Create FalkorDB Standalone with Extra Configuration

To create a standalone FalkorDB cluster with additional custom configurations that are appended to the `redis.conf` file:

```bash
kubectl apply -f examples/falkordb/extra-config.yaml
```

This example demonstrates how to mount an additional ConfigMap containing custom FalkorDB (Redis) configuration parameters. The configuration in the ConfigMap will be appended to the default `redis.conf` file.

```yaml
# snippet of extra-config.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: falkordb
      volumes:
        - name: falkordb-config-extra
          configMap:
            name: falkordb-config-extra
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: falkordb-config-extra
  namespace: demo
data:
  redis.conf: |
    always-show-logo yes
    # Add any additional redis.conf parameters here
```

The volume named `falkordb-config-extra` mounts the ConfigMap, and any configuration parameters defined in the `redis.conf` key will be merged with the base configuration. This allows you to customize FalkorDB behavior without modifying the base configuration templates.

> [!NOTE]
> Make sure to create the ConfigMap in the same namespace as your cluster before creating the cluster resource.

#### Create FalkorDB with Multiple Shards

To create a falkordb sharding cluster (An official distributed FalkorDB)  with 3 shards and 2 replica for each shard:

```bash
kubectl apply -f examples/falkordb/cluster-sharding.yaml
```

You may change the number of shards and replicas in the yaml file.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  shardings:
  - name: shard
    shards: 3  # set the desired number of shards.
    template:
      name: falkordb
      componentDef: falkordb-cluster-4
      replicas: 2 # set the desired number of replicas for each shard.
      serviceVersion: 4.12.5
      # Component-level services override services defined in
      # referenced ComponentDefinition and expose
      # endpoints that can be accessed by clients
      # This example explicitly override the svc `falkordb-advertised` to use the NodePort
      services:
      - name: falkordb-advertised # This is a per-pod svc, and will be used to parse advertised endpoints
        podService: true
        #  - NodePort
        #  - LoadBalancer
        serviceType: NodePort
  ...
```

In this example we demonstrate how to create a FalkorDB cluster with multiple shards, and how to override the service type of the `falkordb-advertised` service to `NodePort`.

The service `falkordb-advertised` is defined in `ComponentDefinition` and will be used to parse the advertised endpoints of the FalkorDB pods.

By default, the service type is `NodePort`. If you want to expose the service to the outside of the cluster, you can override the service type to `NodePort` or `LoadBalancer` depending on your need.

Similarly to add or remove shards, you can update the `shardings` field in the `Cluster` resource.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  shardings:
  - name: shard
    shards: 3 # increase or decrease the number of shards.
    template:
      name: falkordb
      componentDef: falkordb-cluster-4
      replicas: 2 # set the desired number of replicas for each shard.
      serviceVersion: 4.12.5
      stop: false # set to `true` to stop all components
```

## Reference

[^1]: Sentinel: <https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/>
[^2]: Grafana Dashboard Store: <https://grafana.com/grafana/dashboards/>
[^3]: Redis Exporter Metrics: <https://github.com/oliver006/redis_exporter>
