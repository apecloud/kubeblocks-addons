# MongoDB on KubeBlocks

MongoDB is a document database designed for ease of application development and scaling

## Features in KubeBlocks

### Supported Topologies

| Topology      |
|---------------|
| **replicaset** |

A MongoDB replica set[^1] is a group of MongoDB servers that maintain the same dataset, providing high availability and data redundancy. Replica sets are the foundation of MongoDB's fault tolerance and data reliability. By replicating data across multiple nodes, MongoDB ensures that if one server fails, another can take over seamlessly without affecting the application's availability.

In a replica set, there are typically three types of nodes:

- Primary Node: Handles all write operations and serves read requests by default.
- Secondary Nodes: Maintain copies of the primary's data and can optionally serve read requests.
- Arbiter Node: Participates in elections but does not store data. It is used to maintain an odd number of voting members in the replica set.

And it is recommended to create a cluster with at least **three** nodes to ensure high availability, one primary and two secondary nodes.

### Cluster Management Operations

| Operation | Description | Supported |
|-----------|----------------------|--------------|
| **Restart** |• Ordered sequence (followers first)<br/>• Health checks between restarts |  Yes |
| **Stop/Start** | • Graceful shutdown<br/>• Fast startup from persisted state  | Yes |
| **Horizontal Scaling** | • Adjust replica count dynamically<br/>• Automatic data replication<br/> | Yes |
| **Vertical Scaling** |   • Adjust CPU/Memory resources<br/>• Rolling updates for minimal downtime | Yes |
| **Volume Expansion** |   • Online storage expansion<br/>• No downtime required | Yes |
| **Reconfiguration** |  •Static parameter updates<br/>• Validation rules<br/>• Versioned history | No |
| **Service Exposure** |  • Multiple exposure types (ClusterIP/NodePort/LB)<br/>• Role-based routing | Yes |
| **Switchover** | • Planned primary transfer<br/>• Zero data loss guarantee | Yes |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Full Backup | dump   | uses `mongodump`, a MongoDB utility used to create a binary export of the contents of a database  |
| Full Backup | datafile | backup the data files of the database |
| Continuous Backup | archive-oplog |Continuously archives MongoDB oplog using `wal-g` |

### Versions

| Major Versions | Description |
|---------------|--------------|
| 4.0 | 4.0.28,4.2.24,4.4.29 |
| 5.0 | 5.0.28 |
| 6.0 | 6.0.22,6.0.20 |
| 7.0 | 7.0.19,7.0.16,7.0.12 |
| 8.0 | 8.0.8,8.0.6,8.0.4|

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes Environment**:
   - Cluster v1.21+
   - `kubectl` installed ([Installation Guide](https://kubernetes.io/docs/tasks/tools/))
   - Helm v3+ ([Installation Guide](https://helm.sh/docs/intro/install/))

2. **KubeBlocks Setup**:
   - KubeBlocks installed and running ([Installation](../docs/prerequisites.md))
   - MongoDB Addon enabled ([Addon Setup](../docs/install-addon.md))

3. **Namespace Setup**:
   Create an isolated namespace for this tutorial:

  ```bash
  kubectl create ns demo
  ```

## Lifecycle Management Operations

### Cluster Provisioning

#### Quick Start

Create a MongoDB replicaset cluster with 1 primary replica and 2 secondary replicas:

```bash
kubectl apply -f examples/mongodb/cluster.yaml
```

To check the roles of the pods, you can use following command:

```bash
# replace `mongo-cluster` with your cluster name
kubectl get po -n demo -l  app.kubernetes.io/instance=mongo-cluster -L kubeblocks.io/role
```

#### Version-Specific Cluster

If you want to create a cluster of specified version, set the `spec.componentSpecs.serviceVersion` field in the yaml file before applying it:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mongodb
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      serviceVersion: "7.0.19" # more MongoDB versions will be supported in the future
```

The list of supported versions can be found by following command:

```bash
kubectl get cmpv mongodb
```

<details open>
<summary>Expected Output</summary>

```bash
NAME      VERSIONS                                                                                         STATUS      AGE
mongodb   8.0.8,8.0.6,8.0.4,7.0.19,7.0.16,7.0.12,6.0.22,6.0.20,6.0.16,5.0.30,5.0.28,4.4.29,4.2.24,4.0.28   Available    5d
```

</details>

#### Turn on HostNetwork Mode

Optionally, you can create a cluster using HostNetwork mode, by turning on this feature-gate using annotation.
KubeBlocks will allocate AVAILABLE ports for the components.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  annotations:
    # `kubeblocks.io/host-network` is a reserved annotation
    # it defines the feature gate to enable the host-network for specified components or shardings.
    kubeblocks.io/host-network: mongodb
spec:
```

To create a MongoDB cluster running with HostNetwork:

```bash
kubectl apply -f examples/mongodb/cluster-hostnetwork.yaml
```

As mentioned before, to avoid ports conflicts, KubeBlocks will allocate ports for the components on provision.
Please check the ports info when the cluster started, instead of using default ones.

### Cluster Restart

Restart MongoDB component only,

```bash
kubectl apply -f examples/mongodb/restart.yaml
```

This operation restart only one component (MongoDB), as specified in

```yaml
  restart:
  - componentName: mongodb
```

You may list more components as needed.

This operation can only be performed via `OpsRequest`, and there is no corresponding CLUSTER API operation - because restart is not a declaration but an action.

> [!NOTE]
> The restart follows a safe sequence:
>
> 1. All secondary replicas are restarted first
> 2. Primary replica is restarted last
> 3. Transfer leadership to a healthy secondary before restarting Primary replica
> This ensures continuous availability during the restart process.

### Cluster Stop and Start

#### Stopping the Cluster

Gracefully stop the cluster to conserve resources while retaining all data (PVC). It is ideal for cost savings during inactive periods.

**Stop via OpsRequest**

```bash
kubectl apply -f examples/mongodb/stop.yaml
```

> [!NOTE]
> When stopped:
>
> - All compute resources are released
> - Persistent volumes remain intact
> - No data is lost

**Stop via Cluster API**

Update the cluster spec directly:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mongodb
      stop: true  # Set to true to stop the component
      replicas: 3
```

#### Starting the Cluster

Start the cluster from its stopped state:

**Start via OpsRequest**

```bash
kubectl apply -f examples/mongodb/start.yaml
```

**Start via Cluster API**

Update the cluster spec directly:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mongodb
      stop: false  # Set to false to start the component or remove the field (default to false)
      replicas: 3
```

## Scaling Operations

### Horizontal Scaling

> [!NOTE]
> The number of MongoDB replicas should be odd to avoid split-brain scenarios.

On horizontal scaling in/out, member list of the replica set will be updated to make sure the cluster is healthy.
You may verify the full list of members in the replica set by connecting to any pod, and  running the following command:

```bash
mongo-cluster-mongodb > rs.status();
```

#### Scale Out Operation

Add a new replica to the cluster:

```bash
kubectl apply -f examples/mongodb/scale-out.yaml
```

To Check detailed operation status

```bash
kubectl describe ops -n demo mongo-scale-out
```

**Expected Workflow**:

1. New pod is provisioned with `Pending` status
2. Data is cloned from primary to new replica once replication-ship is set
3. New pod transitions to `Running` with `secondary` role
4. Cluster status changes from `Updating` to `Running`

> [!IMPORTANT]
> Scaling considerations:
>
> - Scaling operations are sequential - one replica at a time
> - Data cloning may take time depending on dataset size

To verify the new replica's status:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=mongo-cluster -L kubeblocks.io/role
```

### Scale In Operation

> [!NOTE]
> If the replica being scaled-in happens to be the primary replicas, KubeBlocks will trigger a SwitchOver action (if defined).

#### Standard Scale In Operation

Remove a replica from the cluster:

```bash
kubectl apply -f examples/mongodb/scale-in.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo mongo-scale-in
```

**Expected Workflow**:

1. Selected replica (the one with the largest ordinal) is removed
2. Pod is terminated gracefully
3. Cluster status changes from `Updating` to `Running`

**Verification**:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=mongo-cluster
```

#### Targeted Instance Scale In

For cases where you need to take a specific problematic replica offline for maintenance:

```bash
kubectl apply -f examples/mongodb/scale-in-specified-pod.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo mongo-scale-in-specified-pod
```

**Expected Workflow**:

1. Selected replica (specified in `onlineInstancesToOffline`) is removed
2. Pod is terminated gracefully
3. Cluster status changes from `Updating` to `Running`
4. cluster spec has been updated to:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    name: MongoDB
    offlineInstances:
      - mongo-cluster-mongodb-1  # the instance name specified in opsrequest
    replicas: 1  # replicas reduced by one at the same time.
```

#### Horizontal Scaling via Cluster API

Directly update replica count via Cluster API:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: MongoDB
      replicas: 2  # Adjust replicas for scaling in and out.
      offlineInstances:
        - mongo-cluster-mongodb-1  # for targetd-instance scale-in scenario, default to empty list.
```

### Vertical Scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:

- CPU cores/processing power
- Memory (RAM)

#### Vertical Scaling via OpsRequest API

Perform vertical scaling on MongoDB Component using a operation request:

```bash
kubectl apply -f examples/mongodb/verticalscale.yaml
```

**Expected Workflow**:

1. Secondaries are updated first (one at a time)
1. Primary is updated last after followers are healthy
1. Cluster status transitions from `Updating` to `Running`

#### Vertical Scaling via Cluster API

Directly modify cluster specifications for vertical scaling:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mongodb
      resources:
        requests:
          cpu: "1"       # CPU cores (e.g. "1", "500m")
          memory: "2Gi"  # Memory (e.g. "2Gi", "512Mi")
        limits:
          cpu: "2"       # Maximum CPU allocation
          memory: "4Gi"  # Maximum memory allocation
```

**Key Considerations**:

- Ensure sufficient cluster capacity exists
- Resource changes may trigger pod restarts and parameters reconfiguration
- Monitor resource utilization after changes

## High Availability

### Switchover (Planned Primary Transfer)

SwitchOver is a controlled operation that safely transfers leadership while maintaining:

- Continuous availability
- Zero data loss
- Minimal performance impact

<details>
<summary>Developer: Switchover Actions</summary>
KubeBlocks executes SwitchOver actions defined in `componentdefinition.spec.lifecycleActions.switchover`.

To get the SwitchOver actions for MongoDB:

```bash
kubectl get cmpd mongodb-1.0.0-alpha.0 -oyaml | yq '.spec.lifecycleActions.switchover'
```

</details>

#### Prerequisites

- Cluster must be in `Running` state
- No ongoing maintenance operations

#### Switchover Types

1. **Automatic Switchover** (No preferred candidate):

   ```bash
   kubectl apply -f examples/mongodb/switchover.yaml
   ```

2. **Targeted Switchover** (Specific instance):

   ```bash
   kubectl apply -f examples/mongodb/switchover-specified-instance.yaml
   ```

   Update `opsrequest.spec.switchover.candidateName` as needed

#### Monitoring Switchover

1. **Track Progress**:

   ```bash
   kubectl get ops -n demo -w
   kubectl describe ops <switchover-name> -n demo
   ```

2. **Verify Completion**:

   ```bash
   kubectl get pods -n demo -L kubeblocks.io/role
   ```

#### Troubleshooting

- **Switchover Stuck**:

  ```bash
  kubectl logs -n demo <pod-name> -c kbagent # check on primary replica
  kubectl get events -n demo --field-selector involvedObject.name=mongo-cluster
  ```

## Storage Operations

### Prerequisites

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created. It is introduced in Kubernetes v1.11 and goes GA in Kubernetes v1.24. It allows Kubernetes users to simply edit their PersistentVolumeClaim objects without requiring any downtime at all if possible.

> [!NOTE]
> Make sure the storage class you used when creating clusters supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

### Volume Expansion

#### Volume Expansion via OpsRequest API

To increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/mongodb/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=mongo-cluster -n demo
```

#### Volume Expansion via Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mongodb
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: "<STORAGE_CLASS_NAME>"
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 30Gi  # specify new size, and make sure it is larger than the current size
```

> [!NOTE]
> If the storage class you use does not support volume expansion, this OpsRequest fails fast with information like:
> `storageClass: [STORAGE_CLASS_NAME] of volumeClaimTemplate: [VOLUME_NAME]] not support volume expansion in component [COMPONENT_NAME]`

## Networking

### Service Exposure

1. **Choose Exposure Method**:
   - OpsRequest API
   - Cluster API

2. **Configure Service Annotation** (if using LoadBalancer):
   - Add appropriate annotations

#### Expose SVC via OpsRequest API

- Enable Service

```bash
kubectl apply -f examples/mongodb/expose-enable.yaml
```

- Disable Service

```bash
kubectl apply -f examples/mongodb/expose-disable.yaml
```

#### Expose SVC via Cluster API

Alternatively, you may expose service by adding a new service to cluster's `spec.services`:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  services:
    - annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: nlb  # Use Network Load Balancer
        service.beta.kubernetes.io/aws-load-balancer-internal: "true"  # or "false" for internet
      componentSelector: mongodb
      name: mongodb-internet
      roleSelector: primary
      serviceName: mongodb-internet
      spec:
        ports:
        - name: mongodb
          nodePort: 32749
          port: 27017
          protocol: TCP
          targetPort: mongodb
        type: LoadBalancer  # [ClusterIP, NodePort, LoadBalancer]
```

#### Cloud Provider Load Balancer Annotations

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

## Data Protection Operations

### Prerequisites

1. **Backup Repository**:
   - Configured `BackupRepo` ([Setup Guide](../docs/create-backuprepo.md))
   - Network connectivity between cluster and repo, `BackupRepo` status is `Ready`

2. **Cluster State**:
   - Cluster must be in `Running` state
   - No ongoing operations (scaling, upgrades etc.)

### Backup Operations

#### Backup Configuration

1. **View default Backup Policies**:

   ```bash
   kubectl get backuppolicy -n demo -l app.kubernetes.io/instance=mongo-cluster
   ```

2. **View default BackupSchedule**:

   ```bash
   kubectl get backupschedule -n demo -l app.kubernetes.io/instance=mongo-cluster
   ```

#### Full Backup: datafile

The `datafile` method backup the data files of the database

1. **On-Demand Backup**:

   ```bash
   kubectl apply -f examples/mongodb/backup.yaml
   ```

2. **Monitor Progress**:

   ```bash
   kubectl get backup -n demo -w
   kubectl describe backup <backup-name> -n demo
   ```

3. **Verify Completion**:
   - Check status is `Completed`
   - Verify backup size matches expectations
   - Validate backup metadata

#### Full Backup: dump

The `dump` method uses `mongodump`, a MongoDB utility used to create a binary export of the contents of a database

1. **On-Demand Backup**:

   ```bash
   kubectl apply -f examples/mongodb/backup-dump.yaml
   ```

2. **Monitor Progress**:

   ```bash
   kubectl get backup -n demo -w
   kubectl describe backup <backup-name> -n demo
   ```

3. **Verify Completion**:
   - Check status is `Completed`
   - Verify backup size matches expectations
   - Validate backup metadata

#### Continuous Backup: archive-oplog

This method uses `wal-g` to perform continuous backup :

- Continuously archives MongoDB oplog using wal-g
- Uses datasafed as storage backend with zstd compression
- Maintains backup metadata including size and time ranges
- Automatically purges expired backups
- Verifies MongoDB primary status and process health

#### Scheduled Backups

Update `BackupSchedule` to schedule enable(`enabled`) backup methods and set the time (`cronExpression`) to your need:

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
spec:
  backupPolicyName: mongo-cluster-MongoDB-backup-policy
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
    enabled: true # set to `true` to schedule base backup periodically
    retentionPeriod: 7d # set the retention period to your need
  - backupMethod: archive-oplog
    cronExpression: '*/30 * * * *'
    enabled: true   # set to `true` to enable continuous backup
    name: archive-oplog
    retentionPeriod: 8d # by default, retentionPeriod of continuous backup is 1d more than that of a full backup.
```

#### Troubleshooting

- **Backup Stuck**:

  ```bash
  kubectl describe backup <name> -n demo  # describe backup
  kubectl get po -n demo -l app.kubernetes.io/instance=mongo-cluster,dataprotection.kubeblocks.io/backup-policy=mongo-cluster-mongodb-backup-policy # get list of pods working for Backups
  kubectl logs -n demo <backup-pod> # check backup pod logs
  ```

### Restore Operations

#### Prerequisites

1. **Backup Verification**:
   - Full Backup must be in `Completed` state
   - Continuous Backup must be in `Completed` or `Running` phase, with a valid `timeRange` in status.

2. **Cluster Resources**:
   - Sufficient CPU/memory for new cluster
   - Available storage capacity
   - Network connectivity between backup repo and new cluster

3. **Credentials**:
   - System account encryption keys

#### Restore from a Full Backup

1. **Identify Backup**:

   ```bash
   kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Full,app.kubernetes.io/instance=mongo-cluster # get the list of full backups
   ```

2. **Prepare Credentials**:

   ```bash
   # Get encrypted system accounts
    kubectl get backup <backupName> -n demo -ojson | jq -r '.metadata.annotations | ."kubeblocks.io/encrypted-system-accounts" | fromjson .mongodb | tojson |gsub("\""; "\\\"")'
   ```

3. **Configure Restore**:
   Update `examples/mongodb/restore.yaml` with:
   - Backup name and namespace: from step 1
   - Encrypted system accounts: from step 2
   - Target cluster configuration

4. **Execute Restore**:

   ```bash
   kubectl apply -f examples/mongodb/restore.yaml
   ```

5. **Monitor Progress**:

   ```bash
   # Watch restore status
   kubectl get restore -n demo -w

   # View detailed logs
   kubectl get cluster -n demo -w
   ```

#### Point-in-time Restore

1. **Identify Continuous Backup**

  Check Continuous Backup info:

  ```bash
  # expect EXACTLY ONE continuous backup
  kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Continuous,app.kubernetes.io/instance=mongo-cluster  # get the list of Continuous backups
  ```

  Check `timeRange`:

  ```bash
  kubectl -n demo get backup <backup-name> -oyaml | yq '.status.timeRange' # get a valid time range.
  ```

  expected output likes:

  ```text
  end: "2025-05-10T04:47:16Z"
  start: "2025-05-10T04:44:13Z"
  ```

  Check the list of Full Backups info:

  ```bash
  # expect one or more Full backups
  kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Full,app.kubernetes.io/instance=mongo-cluster  # get the list of Full backups
  ```

> [!IMPORTANT]
> Make sure this is a full backup meets the condition:
>
> its stopTime/completionTimestamp must **AFTER** Continuous backup's startTime.
>
> KubeBlocks will automatically pick the latest completed Full backup as the base backup.

2. **Prepare Credentials**:

  ```bash
  # Get encrypted system accounts
  kubectl get backup <backup-name> -n demo -ojson | jq -r '.metadata.annotations | ."kubeblocks.io/encrypted-system-accounts" | fromjson .mongodb | tojson |gsub("\""; "\\\"")'
  ```

3. **Configure Restore**:
   Update `examples/mongodb/restore-pitr.yaml` with:
   - Backup name and namespace: from step 1
   - Point time: falls in `timeRange` from Step 1
   - Encrypted system accounts: from step 2
   - Target cluster configuration

4. **Execute Restore**:

   ```bash
   kubectl apply -f examples/mongodb/restore-pitr.yaml
   ```

5. **Monitor Progress**:

   ```bash
   # Watch restore status
   kubectl get restore -n demo -w

   # View detailed logs
   kubectl get cluster -n demo -w
   ```

> [!NOTE]
> Restored Cluster is not necessary of the same resources/replicas/storage class/storage size as the one restored from.

## Cleanup

To permanently delete the cluster and all associated resources:

1. First modify the termination policy to ensure all resources are cleaned up:

```bash
# Set termination policy to WipeOut (deletes all resources including PVCs)
kubectl patch cluster -n demo mongo-cluster \
  -p '{"spec":{"terminationPolicy":"WipeOut"}}' \
  --type="merge"
```

2. Verify the termination policy was updated:

```bash
kubectl get cluster -n demo mongo-cluster -o jsonpath='{.spec.terminationPolicy}'
```

3. Delete the cluster:

```bash
kubectl delete cluster -n demo mongo-cluster
```

> [!WARNING]
> This operation is irreversible and will permanently delete:
>
> - All database pods
> - Persistent volumes and claims
> - Services and other cluster resources

<details open>
<summary>How to set a proper `TerminationPolicy`</summary>

For more details you may use following command

```bash
kubectl explain cluster.spec.terminationPolicy
```

| Policy            | Description                                                                                                                                               |
|-------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| `DoNotTerminate`  | Prevents deletion of the Cluster. This policy ensures that all resources remain intact.                                                                   |
| `Delete`          | Deletes all runtime resources belonging to the Cluster.                                                                                                   |
| `WipeOut`         | An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss. |

</details>

## Appendix

### Connecting to MongoDB

To connect to the MongoDB cluster, you can:

- port forward the MongoDB service to your local machine:

```bash
kubectl port-forward svc/mongo-cluster-mongodb-mongodb 27017:27017 -n demo
```

- or expose the MongoDB service to the internet, as mentioned in the [Networking](#networking) section.

Then you can connect to the MongoDB cluster with the following command:

```bash
mongosh "mongodb://<userName>:<userPasswd>@<host>:27017/admin"
```

and credentials can be found in the `secret` resource:

```bash
userName=$(kubectl get secret -n demo mongo-cluster-mongodb-account-root -ojsonpath='{.data.username}' | base64 -d)
userPasswd=$(kubectl get secret -n demo mongo-cluster-mongodb-account-root -ojsonpath='{.data.password}' | base64 -d)
```

### List of K8s Resources created when creating an MongoDB Cluster

To get the full list of associated resources created by KubeBlocks for given cluster:

```bash
kubectl get cmp,its,po -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # cluster and worload
kubectl get backuppolicy,backupschedule,backup -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # data protection resources
kubectl get componentparameter,parameter -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # configuration resources
kubectl get opsrequest -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # opsrequest resources
kubectl get svc,secret,cm,pvc -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # k8s native resources
```

### How to check if a Component supports HostNetwork mode

Not all KubeBlocks Addons supports running HostNetwork mode.
Please find out whether a component supports this feature or not, you may check its `ComponentDefinition`:

```bash
kubectl get cmpd <componentDefName> -oyaml | yq '.spec.hostNetwork'
```

This feature is supported if above output is not nil.

For instance, by checking MongoDB

```bash
kubectl get cmpd mongodb-1.0.0-alpha.0 -oyaml | yq '.spec.hostNetwork'
```

the output is:

```text
containerPorts:
  - container: mongodb
    ports:
      - mongodb
      - ha
```

But when checking MySQL:

```bash
kubectl get cmpd  mysql-8.0-1.0.0-alpha.0 -oyaml |  yq '.spec.hostNetwork'
```

The output is

```txt
null
```

## References

[^1]: MongoDB Replica Set, <https://www.mongodb.com/docs/manual/replication/>
