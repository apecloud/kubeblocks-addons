# PostgreSQL

PostgreSQL (Postgres) is an open source object-relational database known for reliability and data integrity. ACID-compliant, it supports foreign keys, joins, views, triggers and stored procedures.

## Features In KubeBlocks

### Lifecycle Management

|   Topology       | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| replication     | Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | Yes      |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Full Backup | pg-basebackup   | uses `pg_basebackup`,  a PostgreSQL utility to create a base backup   |
| Full Backup | postgres-wal-g   | uses `wal-g` to create a full backup (and don't forget to config wal-g by setting envs ahead) |
| Continuous Backup | postgresql-pitr | uploading PostgreSQL Write-Ahead Logging (WAL) files periodically to the backup repository. |

### Versions

| Major Versions | Description |
|---------------|-------------|
| 12            | 12.14.0,12.14.1,12.15.0,12.22.0|
| 14            | 14.7.2,14.8.0,14.18.0|
| 15            | 15.7.0,15.13.0|
| 16            | 16.4.0,16.9.0|
| 17            | 17.5.0|

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- PostgreSQL Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

Create a PostgreSQL cluster with one primary and one secondary instance:

```yaml
# cat examples/postgresql/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pg-cluster
  namespace: demo
spec:
  # Specifies the behavior when a Cluster is deleted.
  # Valid options are: [DoNotTerminate, Delete, WipeOut] (`Halt` is deprecated since KB 0.9)
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies the name of the ClusterDefinition to use when creating a Cluster.
  # Note: DO NOT UPDATE THIS FIELD
  # The value must be `postgresql` to create a PostgreSQL Cluster
  clusterDef: postgresql
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  # Valid options are: [replication]
  topology: replication
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: postgresql
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [12.14.0,12.14.1,12.15.0,12.22.0,14.7.2,14.8.0,14.18.0,15.7.0,15.13.0,16.4.0,16.9.0,17.5.0]
      serviceVersion: "14.7.2"
      # Determines whether metrics exporter information is annotated on the
      # Component's headless Service.
      # Valid options are [true, false]
      disableExporter: false
      # Specifies Labels to override or add for underlying Pods, PVCs, Account & TLS
      # Secrets, Services Owned by Component.
      labels:
        # PostgreSQL's CMPD specifies `KUBERNETES_SCOPE_LABEL=apps.kubeblocks.postgres.patroni/scope` through ENVs
        # The KUBERNETES_SCOPE_LABEL is used to define the label key that Patroni will use to tag Kubernetes resources.
        # This helps Patroni identify which resources belong to the specified scope (or cluster) used to define the label key
        # that Patroni will use to tag Kubernetes resources.
        # This helps Patroni identify which resources belong to the specified scope (or cluster).
        #
        # Note: DO NOT REMOVE THIS LABEL
        # update the value w.r.t your cluster name
        # the value must follow the format <cluster.metadata.name>-postgresql
        # which is pg-cluster-postgresql in this examples
        # replace `pg-cluster` with your cluster name
        apps.kubeblocks.postgres.patroni/scope: pg-cluster-postgresql
      # Update `replicas` to your need.
      replicas: 2
      # Specifies the resources required by the Component.
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      # Specifies a list of PersistentVolumeClaim templates that define the storage
      # requirements for the Component.
      volumeClaimTemplates:
        # Refers to the name of a volumeMount defined in
        # `componentDefinition.spec.runtime.containers[*].volumeMounts
        - name: data
          spec:
            # The name of the StorageClass required by the claim.
            # If not specified, the StorageClass annotated with
            # `storageclass.kubernetes.io/is-default-class=true` will be used by default
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                # Set the storage size as needed
                storage: 20Gi
```

```bash
kubectl apply -f examples/postgresql/cluster.yaml
```

And you will see the PostgreSQL cluster status goes `Running` after a while:

```bash
kubectl get cluster -n demo pg-cluster
```

and two pods are `Running` with roles `primary` and `secondary` separately. To check the roles of the pods, you can use following command:

```bash
# replace `pg-cluster` with your cluster name
kubectl get po -l  app.kubernetes.io/instance=pg-cluster -L kubeblocks.io/role -n demo
# or login to the pod and use `patronictl` to check the roles:
kubectl exec -it pg-cluster-postgresql-0 -n demo -- patronictl list
```

If you want to create a PostgreSQL cluster of specified version, set the `spec.componentSpecs.serviceVersion` field in the yaml file before applying it:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  terminationPolicy: Delete
  clusterDef: postgresql
  topology: replication
  componentSpecs:
    - name: postgresql
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [12.14.0,12.14.1,12.15.0,12.22.0,14.7.2,14.8.0,14.18.0,15.7.0,15.13.0,16.4.0,16.9.0,17.5.0]
      serviceVersion: "14.7.2"
```

The list of supported versions can be found by following command:

```bash
kubectl get cmpv postgresql
```

And the expected output is like:

```bash
NAME         VERSIONS                                                                                    STATUS      AGE
postgresql   17.5.0,16.9.0,16.4.0,15.13.0,15.7.0,14.18.0,14.8.0,14.7.2,12.22.0,12.15.0,12.14.1,12.14.0   Available   Xd
```

### Horizontal scaling

#### Scale-out

Horizontal scaling out PostgreSQL cluster by adding ONE more replica:

```yaml
# cat examples/postgresql/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: postgresql
    # Specifies the replica changes for scaling out components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/postgresql/scale-out.yaml
```

After applying the operation, you will see a new pod created and the PostgreSQL cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `secondary`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe -n demo ops pg-scale-out
```

#### Scale-in

Horizontal scaling in PostgreSQL cluster by deleting ONE replica:

```yaml
# cat examples/postgresql/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: postgresql
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/postgresql/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: postgresql
      serviceVersion: "14.7.2"
      labels:
        apps.kubeblocks.postgres.patroni/scope: pg-cluster-postgresql
      replicas: 2 # Update `replicas` to 1 for scaling in, and to 3 for scaling out
```

### Vertical scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```yaml
# cat examples/postgresql/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: postgresql
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/postgresql/verticalscale.yaml
```

You will observe that the `secondary` pod is recreated first, followed by the `primary` pod, to ensure the availability of the cluster.

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: postgresql
      replicas: 2
      resources:
        requests:
          cpu: "1"       # Update the resources to your need.
          memory: "2Gi"  # Update the resources to your need.
        limits:
          cpu: "2"       # Update the resources to your need.
          memory: "4Gi"  # Update the resources to your need.
```

### Expand volume

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created. It is introduced in Kubernetes v1.11 and goes GA in Kubernetes v1.24. It allows Kubernetes users to simply edit their PersistentVolumeClaim objects  without requiring any downtime at all if possible[^4].

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

To increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/postgresql/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: postgresql
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/postgresql/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=pg-cluster -n demo
```

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: postgresql
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

### Restart

Restart the specified components in the cluster, and instances will be recreated on after another to ensure the availability of the cluster

```yaml
# cat examples/postgresql/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: postgresql

```

```bash
kubectl apply -f examples/postgresql/restart.yaml
```

### Stop

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```yaml
# cat examples/postgresql/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  type: Stop

```

```bash
kubectl apply -f examples/postgresql/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: postgresql
      stop: true  # set stop `true` to stop the component
      replicas: 2
```

### Start

Start the stopped cluster

```yaml
# cat examples/postgresql/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  type: Start

```

```bash
kubectl apply -f examples/postgresql/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: postgresql
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 2
```

### Switchover

A switchover in database clusters is a planned operation that transfers the primary (leader) role from one database instance to another. The goal of a switchover is to ensure that the database cluster remains available and operational during the transition.

#### Switchover without preferred candidates

To perform a switchover without any preferred candidates, you can apply the following yaml file:

```yaml
# cat examples/postgresql/switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-switchover
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: postgresql
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: pg-cluster-postgresql-0

```

```bash
kubectl apply -f examples/postgresql/switchover.yaml
```

<details>
<summary>Details</summary>

By applying this yaml file, KubeBlocks will perform a switchover operation defined in PostgreSQL's component definition, and you can checkout the details in `componentdefinition.spec.lifecycleActions.switchover`.

You may get the switchover operation details with following command:

```bash
kubectl get cluster -n demo pg-cluster -ojson | jq '.spec.componentSpecs[0].componentDef' | xargs kubectl get cmpd -ojson | jq '.spec.lifecycleActions.switchover'
```

</details>

#### Switchover with candidate specified

Switchover a specified instance as the new primary or leader of the cluster

```yaml
# cat examples/postgresql/switchover-specified-instance.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-switchover-specify
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: postgresql
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: pg-cluster-postgresql-0
    # If CandidateName is specified, the role will be transferred to this instance.
    # The name must match one of the pods in the component.
    # Refer to ComponentDefinition's Swtichover lifecycle action for more details.
    candidateName: pg-cluster-postgresql-1

```

```bash
kubectl apply -f examples/postgresql/switchover-specified-instance.yaml
```

You may need to update the `opsrequest.spec.switchover.instanceName` field to your desired instance name.

Once this `opsrequest` is completed, you can check the status of the switchover operation and the roles of the pods to verify the switchover operation.

### Reconfigure

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```yaml
# cat examples/postgresql/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-reconfiguring
  namespace: demo
spec:
  # Specifies the type of this operation.
  type: Reconfiguring
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: postgresql
    parameters:
      # Represents the name of the parameter that is to be updated.
      # `max_connections` is a dyamic parameter in PostgreSQL that can be changed or updated at runtime without requiring a restart of the database
    - key: max_connections
      # Represents the parameter values that are to be updated.
      # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
      value: '200'
```

```bash
kubectl apply -f examples/postgresql/configure.yaml
```

This example will change the `max_connections` to `200`.
> `max_connections` indicates maximum number of client connections allowed. It is a dynamic parameter, so the change will take effect without restarting the database.

```bash
kbcli cluster explain-config pg-cluster # kbcli is a command line tool to interact with KubeBlocks
```

### Backup

> [!IMPORTANT]
> Before you start, please create a `BackupRepo` to store the backup data. Refer to [BackupRepo](../docs/create-backuprepo.md) for more details.

KubeBlocks supports multiple backup methods for PostgreSQL cluster, such as `pg-basebackup`, `volume-snapshot`, `wal-g`, etc.

You may find the supported backup methods in the `BackupPolicy` of the cluster, e.g. `pg-cluster-postgresql-backup-policy` in this case, and find how these methods will be scheduled in the `BackupSchedule` of the cluster, e.g.. `pg-cluster-postgresql-backup-schedule` in this case.

We will elaborate on the `pg-basebackup` and `wal-g` backup methods in the following sections to demonstrate how to create full backup and continuous backup for the cluster.

#### pg_basebackup

##### Full Backup(backup-pg-basebasekup.yaml)

The method `pg-basebackup` uses `pg_basebackup`,  a PostgreSQL utility to create a base backup[^1]

To create a base backup for the cluster, you can apply the following yaml file:

```yaml
# cat examples/postgresql/backup-pg-basebasekup.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: pg-cluster-pg-basebackup
  namespace: demo
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - pg-basebackup
  # - volume-snapshot
  # - config-wal-g and wal-g
  # - archive-wal
  backupMethod: pg-basebackup
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: pg-cluster-postgresql-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete

```

```bash
kubectl apply -f examples/postgresql/backup-pg-basebasekup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -n demo -l app.kubernetes.io/instance=pg-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

Information, such as `path`, `timeRange` about the backup will be recorded into the `Backup` resource.

Alternatively, you can update the `BackupSchedule` to enable the method `pg-basebackup` to schedule base backup periodically, will be elaborated in the following section.

#### Continuous Backup

To enable continuous backup, you need to update `BackupSchedule` and enable the method `archive-wal`.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
metadata:
  name: pg-cluster-postgresql-backup-schedule
  namespace: demo
spec:
  backupPolicyName: pg-cluster-postgresql-backup-policy
  schedules:
  - backupMethod: pg-basebackup
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
  - backupMethod: archive-wal
    cronExpression: '*/5 * * * *'
    enabled: true  # set to `true` to enable continuouse backup
    retentionPeriod: 8d # set the retention period to your need
```

Once the `BackupSchedule` is updated, the continuous backup starts to work, and you can check the status of the backup with following command:

```bash
kubectl get backup -n demo -l app.kubernetes.io/instance=pg-cluster
```

And you will find one `Backup` named with suffix 'pg-cluster-postgresql-archive-wal' is created with the method `archive-wal`.

It will run continuously until you disable the method `archive-wal` in the `BackupSchedule`. And the valid time range of the backup will be recorded in the `Backup` resource:

```bash
kubectl get backup -n demo -l app.kubernetes.io/instance=pg-cluster -l dataprotection.kubeblocks.io/backup-type=Continuous  -oyaml | yq '.items[].status.timeRange'
```

#### wal-g

WAL-G is an archival restoration tool for PostgreSQL, MySQL/MariaDB, and MS SQL Server (beta for MongoDB and Redis).[^2]

##### Full Backup

To create wal-g backup for the cluster, it is a multi-step process.

1. configure WAL-G on all PostgreSQL pods

```yaml
# cat examples/postgresql/config-wal-g.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: pg-cluster-config-wal-g
  namespace: demo
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - pg-basebackup
  # - volume-snapshot
  # - config-wal-g and wal-g
  # - archive-wal
  backupMethod: config-wal-g
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: pg-cluster-postgresql-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`. - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete
```

```bash
kubectl apply -f examples/postgresql/config-wal-g.yaml
```

1. set `archive_command` to `wal-g wal-push %p`

```yaml
# cat examples/postgresql/backup-wal-g.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: pg-cluster-wal-g
  namespace: demo
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - pg-basebackup
  # - volume-snapshot
  # - config-wal-g and wal-g
  # - archive-wal
  backupMethod: wal-g
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: pg-cluster-postgresql-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete

```

```bash
kubectl apply -f examples/postgresql/backup-wal-g.yaml
```

1. you cannot do wal-g backup for a brand-new cluster, you need to insert some data before backup

1. create a backup

```yaml
# cat examples/postgresql/backup-wal-g.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: pg-cluster-wal-g
  namespace: demo
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - pg-basebackup
  # - volume-snapshot
  # - config-wal-g and wal-g
  # - archive-wal
  backupMethod: wal-g
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: pg-cluster-postgresql-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete

```

```bash
kubectl apply -f examples/postgresql/backup-wal-g.yaml
```

> [!NOTE]
> if there is horizontal scaling out new pods after step 2, you need to do config-wal-g again

### Restore

To restore a new cluster from a Backup:

1. Get the list of accounts and their passwords from the backup:

```bash
kubectl get backup -n demo pg-cluster-pg-basebackup -ojsonpath='{.metadata.annotations.kubeblocks\.io/encrypted-system-accounts}'
```

1. Update `examples/postgresql/restore.yaml` and set placeholder `<ENCRYPTED-SYSTEM-ACCOUNTS>` with your own settings and apply it.

```yaml
# cat examples/postgresql/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pg-restore
  namespace: demo
  annotations:
    # NOTE: replace <ENCRYPTED-SYSTEM-ACCOUNTS> with the accounts info from you backup
    kubeblocks.io/restore-from-backup: '{"postgresql":{"encryptedSystemAccounts":"<ENCRYPTED-SYSTEM-ACCOUNTS>","name":"pg-cluster-pg-basebackup","namespace":"demo","volumeRestorePolicy":"Parallel"}}'
spec:
  terminationPolicy: Delete
  clusterDef: postgresql
  topology: replication
  componentSpecs:
    - name: postgresql
      serviceVersion: "14.7.2"
      disableExporter: true
      labels:
        # NOTE: update the label accordingly
        apps.kubeblocks.postgres.patroni/scope: pg-restore-postgresql
      replicas: 2
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
```

```bash
kubectl apply -f examples/postgresql/restore.yaml
```

### Expose

Expose a cluster with a new endpoint

#### Enable

```yaml
# cat examples/postgresql/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-expose-enable
  namespace: demo
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: postgresql
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      # Determines how the Service is exposed. Defaults to 'ClusterIP'.
      # Valid options are `ClusterIP`, `NodePort`, and `LoadBalancer`.
      serviceType: LoadBalancer
      # Contains cloud provider related parameters if ServiceType is LoadBalancer.
      # Following is an example for Aliyun ACK, please adjust the following annotations as needed.
      annotations:
        service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: internet
        service.beta.kubernetes.io/alibaba-cloud-loadbalancer-charge-type: ""
        service.beta.kubernetes.io/alibaba-cloud-loadbalancer-spec: slb.s1.small
      # Specifies a role to target with the service.
      # If specified, the service will only be exposed to pods with the matching
      # role.
      roleSelector: primary
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Enable
```

```bash
kubectl apply -f examples/postgresql/expose-enable.yaml
```

#### Disable

```yaml
# cat examples/postgresql/expose-disable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-expose-disable
  namespace: demo
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: postgresql
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      # Determines how the Service is exposed. Defaults to 'ClusterIP'.
      # Valid options are `ClusterIP`, `NodePort`, and `LoadBalancer`.
      serviceType: LoadBalancer
      roleSelector: primary
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Disable

```

```bash
kubectl apply -f examples/postgresql/expose-disable.yaml
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
    componentSelector: postgresql
    name: postgresql-vpc
    serviceName: postgresql-vpc
    # optional. it specify defined role as selector for the service.
    # onece specified, service will select and route traffic to Pods with the label
    # "kubeblocks.io/role=<specified-role-name>".
    # valid options are: [primary, secondary] for postgresql
    roleSelector: primary
    spec:  # defines the behavior of a K8s service.
      ipFamilyPolicy: PreferDualStack
      ports:
      - name: tcp-postgresql
        # port to expose
        port: 5432
        protocol: TCP
        targetPort: tcp-postgresql
      type: LoadBalancer
```

If the service is of type `LoadBalancer`, please add annotations for cloud loadbalancer depending on the cloud provider you are using[^3]. Here list annotations for some cloud providers:

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

Please consult your cloud provider for more accurate and update-to-date information.

### Upgrade

Upgrade postgresql cluster to another version

```yaml
# cat examples/postgresql/upgrade.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-upgrade
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pg-cluster
  type: Upgrade
  upgrade:
    components:
    - componentName: postgresql
      # Specifies the desired service version of component
      serviceVersion: "14.8.0"
```

```bash
kubectl apply -f examples/postgresql/upgrade.yaml
```

In this example, the cluster will be upgraded to version `14.8.0`.

#### Upgrade using Cluster API

Alternatively, you may modify the `spec.componentSpecs.serviceVersion` field to the desired version to upgrade the cluster.

> [!WARNING]
> Do remember to to check the compatibility of versions before upgrading the cluster.

```bash
kubectl get cmpv postgresql -ojson | jq '.spec.compatibilityRules'
```

Expected output:

```json
[
  {
    "compDefs": [
      "postgresql-12-"
    ],
    "releases": [
      "12.14.0",
      "12.14.1",
      "12.15.0"
    ]
  },
  {
    "compDefs": [
      "postgresql-14-"
    ],
    "releases": [
      "14.7.2",
      "14.8.0"
    ]
  }
]
```

Releases are grouped by component definitions, and each group has a list of compatible releases.
In this example, it shows you can upgrade from version `12.14.0` to `12.14.1` or `12.15.0`, and upgrade from `14.7.2` to `14.8.0`.
But cannot upgrade from `12.14.0` to `14.8.0`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: postgresql
      serviceVersion: "14.8.0" # set to the desired version
      replicas: 2
      resources:
```

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create a Cluster

Create a new cluster with following command:

> [!NOTE]
> Make sure `spec.componentSpecs.disableExporter` is set to `false` when creating cluster.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: postgresql
      serviceVersion: "14.7.2"
      disableExporter: false # set to `false` to enable exporter
```

```yaml
# cat examples/postgresql/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pg-cluster
  namespace: demo
spec:
  # Specifies the behavior when a Cluster is deleted.
  # Valid options are: [DoNotTerminate, Delete, WipeOut] (`Halt` is deprecated since KB 0.9)
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies the name of the ClusterDefinition to use when creating a Cluster.
  # Note: DO NOT UPDATE THIS FIELD
  # The value must be `postgresql` to create a PostgreSQL Cluster
  clusterDef: postgresql
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  # Valid options are: [replication]
  topology: replication
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: postgresql
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [12.14.0,12.14.1,12.15.0,12.22.0,14.7.2,14.8.0,14.18.0,15.7.0,15.13.0,16.4.0,16.9.0,17.5.0]
      serviceVersion: "14.7.2"
      # Determines whether metrics exporter information is annotated on the
      # Component's headless Service.
      # Valid options are [true, false]
      disableExporter: false
      # Specifies Labels to override or add for underlying Pods, PVCs, Account & TLS
      # Secrets, Services Owned by Component.
      labels:
        # PostgreSQL's CMPD specifies `KUBERNETES_SCOPE_LABEL=apps.kubeblocks.postgres.patroni/scope` through ENVs
        # The KUBERNETES_SCOPE_LABEL is used to define the label key that Patroni will use to tag Kubernetes resources.
        # This helps Patroni identify which resources belong to the specified scope (or cluster) used to define the label key
        # that Patroni will use to tag Kubernetes resources.
        # This helps Patroni identify which resources belong to the specified scope (or cluster).
        #
        # Note: DO NOT REMOVE THIS LABEL
        # update the value w.r.t your cluster name
        # the value must follow the format <cluster.metadata.name>-postgresql
        # which is pg-cluster-postgresql in this examples
        # replace `pg-cluster` with your cluster name
        apps.kubeblocks.postgres.patroni/scope: pg-cluster-postgresql
      # Update `replicas` to your need.
      replicas: 2
      # Specifies the resources required by the Component.
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      # Specifies a list of PersistentVolumeClaim templates that define the storage
      # requirements for the Component.
      volumeClaimTemplates:
        # Refers to the name of a volumeMount defined in
        # `componentDefinition.spec.runtime.containers[*].volumeMounts
        - name: data
          spec:
            # The name of the StorageClass required by the claim.
            # If not specified, the StorageClass annotated with
            # `storageclass.kubernetes.io/is-default-class=true` will be used by default
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                # Set the storage size as needed
                storage: 20Gi
```

```bash
kubectl apply -f examples/postgresql/cluster.yaml
```

When the cluster is running, each POD should have a sidecar container, named `exporter` running the postgres-exporter.

#### Create PodMonitor

##### Step 1. Query ScrapePath and ScrapePort

You can retrieve the `scrapePath` and `scrapePort` from pod's exporter container.

```bash
kubectl get po -n demo pg-cluster-postgresql-0 -oyaml | yq '.spec.containers[] | select(.name=="exporter") | .ports '
```

And the expected output is like:

```text
- containerPort: 9187
  name: http-metrics
  protocol: TCP
```

##### Step 2. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/postgresql/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: pg-cluster-pod-monitor
  labels:               # this is labels set in `prometheus.spec.podMonitorSelector`
    release: prometheus
spec:
  jobLabel: app.kubernetes.io/managed-by
  # defines the labels which are transferred from the
  # associated Kubernetes `Pod` object onto the ingested metrics
  # set the lables w.r.t you own needs
  podTargetLabels:
  - app.kubernetes.io/instance
  - app.kubernetes.io/managed-by
  - apps.kubeblocks.io/component-name
  - apps.kubeblocks.io/pod-name
  podMetricsEndpoints:
    - path: /metrics
      port: http-metrics
      scheme: http
  namespaceSelector:
    matchNames:
      - demo
  selector:
    matchLabels:
      app.kubernetes.io/instance: pg-cluster
      apps.kubeblocks.io/component-name: postgresql
```

```bash
kubectl apply -f examples/postgresql/pod-monitor.yaml
```

##### Step 3. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard.

There is a pre-configured dashboard for PostgreSQL under the `APPS / PostgreSQL` folder in the Grafana dashboard. And more dashboards can be found in the Grafana dashboard store[^5].

> [!NOTE]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo pg-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo pg-cluster
```

## Appendix

### How to Create PostgreSQL Cluster with ETCD or Zookeeper as DCS

```yaml
# cat examples/postgresql/cluster-with-etcd.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pg-cluster-etcd
  namespace: demo
spec:
  terminationPolicy: Delete
  clusterDef: postgresql
  topology: replication
  componentSpecs:
    - name: postgresql
      serviceVersion: "14.7.2"
      env:
      - name: DCS_ENABLE_KUBERNETES_API  # unset this env if you use zookeeper or etcd, default to empty
      - name: ETCD3_HOST
        value: 'myetcd-etcd-headless.default.svc.cluster.local:2379' # where is your etcd?
      # - name: ZOOKEEPER_HOSTS
      #   value: 'myzk-zookeeper-0.myzk-zookeeper-headless.default.svc.cluster.local:2181' # where is your zookeeper?
      replicas: 2
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
```

```bash
kubectl apply -f examples/postgresql/cluster-with-etcd.yaml
```

This example will create a PostgreSQL cluster with ETCD as DCS. It will set two envs:

- `DCS_ENABLE_KUBERNETES_API` to empty, unset this env if you use zookeeper or etcd, default to empty
- `ETCD3_HOST` to the ETCD cluster's headless service address, or use `ETCD3_HOSTS` to set ETCD hosts and ports.

Similar for Zookeeper, you can set `ZOOKEEPER_HOSTS` to the Zookeeper's address.

More environment variables can be found in [Spilo's ENVIRONMENT](https://github.com/zalando/spilo/blob/master/ENVIRONMENT.rst).

## Reference

[^1]: pg_basebackup, <https://www.postgresql.org/docs/current/app-pgbasebackup.html>
[^2]: wal-g <https://github.com/wal-g/wal-g>
[^3]: Internal load balancer: <https://kubernetes.io/docs/concepts/services-networking/service/#internal-load-balancer>
[^4]: Volume Expansion: <https://kubernetes.io/blog/2022/05/05/volume-expansion-ga/>
[^5]: Grafana Dashboard Store: <https://grafana.com/grafana/dashboards/>
