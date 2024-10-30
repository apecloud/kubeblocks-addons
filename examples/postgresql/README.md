# Postgresql

PostgreSQL (Postgres) is an open source object-relational database known for reliability and data integrity. ACID-compliant, it supports foreign keys, joins, views, triggers and stored procedures.

## Prerequisites

This example assumes that you have a Kubernetes cluster installed and running, and that you have installed the kubectl command line tool and helm somewhere in your path. Please see the [getting started](https://kubernetes.io/docs/setup/)  and [Installing Helm](https://helm.sh/docs/intro/install/) for installation instructions for your platform.

Also, this example requires KubeBlocks installed and running. Here is the steps to install kubeblocks, please replace "`$kb_version`" with the version you want to use.

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

Create a postgresql cluster with one primary and one secondary instance:

```bash
kubectl apply -f examples/postgresql/cluster.yaml
```

And you will see the postgresql cluster status goes `Running` after a while:

```bash
kubectl get cluster pg-cluster
```

and two pods are `Running` with roles `primary` and `secondary` separately. To check the roles of the pods, you can use following command:

```bash
# replace `pg-cluster` with your cluster name
kubectl get po -l  app.kubernetes.io/instance=pg-cluster -L kubeblocks.io/role -n default
# or login to the pod and use `patronictl` to check the roles:
kubectl exec -it pg-cluster-postgresql-0 -n default -- patronictl list
```

If you want to create a postgresql cluster of specified version, just modify the `spec.componentSpecs.serviceVersion` field in the yaml file before applying it:

```yaml
spec:
  terminationPolicy: Delete
  clusterDef: postgresql
  topology: replication
  componentSpecs:
    - name: postgresql
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [12.14.0,12.14.1,12.15.0,14.7.2,14.8.0,15.7.0,16.4.0]
      serviceVersion: "14.7.2"
```

The list of supported versions can be found by following command:

```bash
kubectl get cmpv postgresql
```

And the expected output is like:

```bash
NAME         VERSIONS                                              STATUS      AGE
postgresql   12.14.0,12.14.1,12.15.0,14.7.2,14.8.0,15.7.0,16.4.0   Available   Xd
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out postgresql cluster by adding ONE more replica:

```bash
kubectl apply -f examples/postgresql/scale-out.yaml
```

After applying the operation, you will see a new pod created and the postgresql cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `secondary`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe ops pg-scale-in
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in postgresql cluster by deleting ONE replica:

```bash
kubectl apply -f examples/postgresql/scale-in.yaml
```

Besides, you can also use `kubectl edit` to scale the cluster:

```bash
kubectl edit cluster pg-cluster
```

And modify the `replicas` field in the `spec.componentSpecs.replicas` section to the desired number.

```yaml
spec:
  componentSpecs:
    - name: postgresql
      serviceVersion: "14.7.2"
      disableExporter: true
      labels:
        apps.kubeblocks.postgres.patroni/scope: pg-cluster-postgresql
      # Update `replicas` to 1 for scaling in, and to 3 for scaling out
      replicas: 2
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling involves increasing or decreasing resources to an existing database clsuter.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```bash
kubectl apply -f examples/postgresql/verticalscale.yaml
```

You will observe that the `secondary` pod is recreated first, followed by the `primary` pod, to ensure the availability of the cluster.

Optionally, you can use `kubectl edit` to scale the cluster, and udpate `spec.componentSpecs.resources` field to the desired resources.

```yaml
spec:
  componentSpecs:
    - name: postgresql
      replicas: 2
      # Update the resources to your need.
      resources:
        requests:
          cpu: "1"
          memory: "2Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
```

### [Expand volume](volumeexpand.yaml)

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created.

> [!NOTE]
> Make sure the storage class you use supports volume expansion.
> You can check the storage class with following command:
>
> ```bash
> kubectl get sc
> ```
>
> If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

To increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/postgresql/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case.
You can check the volume size with following command:

```bash
kubectl get pvc -l app.kubernetes.io/instance=pg-cluster -n default
```

You can also use `kubectl edit` to expand the volume:

```bash
kubectl edit cluster pg-cluster
```

And modify the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
spec:
  componentSpecs:
    - name: postgresql
      volumeClaimTemplates:
        - metadata:
            name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                # update the storage size to your need
                storage: 30Gi
```

### [Restart](restart.yaml)

Restart the specified components in the cluster, and instances will be recreated on after another to ensure the availability of the cluster

```bash
kubectl apply -f examples/postgresql/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```bash
kubectl apply -f examples/postgresql/stop.yaml
```

You can also use `kubectl edit` to stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
spec:
  componentSpecs:
    - name: postgresql
      stop: true  # set stop `true` to stop the component
      replicas: 2
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/postgresql/start.yaml
```

Similary, you can use `kubectl edit` to start the cluster:

```bash
kubectl edit cluster pg-cluster
```

And modify the `spec.componentSpecs.stop` field to `false` or remove the `spec.componentSpecs.stop` field.

```yaml
spec:
  componentSpecs:
    - name: postgresql
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 2
```

### [Switchover](switchover.yaml)

A switchover in database clusters is a planned operation that transfers the primary (leader) role from one database instance to another. The goal of a switchover is to ensure that the database cluster remains available and operational during the transition. To perform a switchover operation, you can apply the following yaml file:

```bash
kubectl apply -f examples/postgresql/switchover.yaml
```

<details>

By applying this yaml file, KubeBlocks will perform a switchover operation defined in postgresql's component definition, and you can checkout the details in `componentdefinition.spec.lifecycleActions.switchover`.

You may get the switchover operation details with following command:

```bash
kubectl get cluster pg-cluster -ojson | jq '.spec.componentSpecs[0].componentDef' | xargs kubectl get cmpd -ojson | jq '.spec.lifecycleActions.switchover'
```

</details>


### [Switchover-specified-instance](switchover-specified-instance.yaml)

Switchover a specified instance as the new primary or leader of the cluster

```bash
kubectl apply -f examples/postgresql/switchover-specified-instance.yaml
```

You may need to modify the `opsrequest.spec.switchover.instanceName` field to your desired `secondary` instance name.

Once this `opsrequest` is completed, you can check the status of the switchover operation and the roles of the pods to verify the switchover operation.

### [Reconfigure](configure.yaml)

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```bash
kubectl apply -f examples/postgresql/configure.yaml
```

This example will change the `max_connections` to `200`.
> `max_connections` indicates maximum number of client connections allowed. It is a dynamic parameter, so the change will take effect without restarting the database.

<details>

To check the full list of parameters that can be reconfigured, you can use following command:

```bash
kbcli cluster explain-config pg-cluster # kbcli is a command line tool to interact with KubeBlocks
```
</details>

### [BackupRepo](backuprepo.yaml)

BackupRepo is the storage repository for backup data. Before creating a BackupRepo, you need to create a secret to save the access key of the backup repository

```bash
# Create a secret to save the access key
kubectl create secret generic <credential-for-backuprepo>\
  --from-literal=accessKeyId=<ACCESS KEY> \
  --from-literal=secretAccessKey=<SECRET KEY> \
  -n kb-system
```

Update `examples/postgresql/backuprepo.yaml` and set fields quoated with `<>` to your own settings and apply it.

```bash
kubectl apply -f examples/postgresql/backuprepo.yaml
```

After creating the BackupRepo, you should check the status of the BackupRepo, to make sure it is `Ready`.

```bash
kubectl get backuprepo
```

And the expected output is like:

```bash
NAME     STATUS   STORAGEPROVIDER   ACCESSMETHOD   DEFAULT   AGE
kb-oss   Ready    oss               Tool           true      Xd
```

### [Backup]

KubeBlocks supports multiple backup methods for postgresql cluster, such as `pg-basebackup`, `volume-snapshot`, `wal-g`, etc.

You may find the supported backup methods in the `BackupPolicy` of the cluster, e.g. `pg-cluster-postgresql-backup-policy` in this case, and find how these methods will be scheduled in the `BackupSchedule` of the cluster, e.g.. `pg-cluster-postgresql-backup-schedule` in this case.

We will elaborate on the `pg-basebackup` and `wal-g` backup methods in the following sections to demonstrate how to create base backup and incremental backup for the cluster.

#### [pg_basebackup]

##### Base Backup(backup-pg-basebasekup.yaml)

The method `pg-basebackup` uses `pg_basebackup`,  a PostgreSQL utility to create a base backup[^1]

To create a base backup for the cluster, you can apply the following yaml file:

```bash
kubectl apply -f examples/postgresql/backup-pg-basebasekup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -l app.kubernetes.io/instance=pg-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

Infomation, such as `path`, `timeRange` about the backup will be recoreded into the `Backup` resource.

Alternatively, you can update the `BackupSchedule` to enable the method `pg-basebackup` to schedule base backup periodically, will be elaborated in the following section.

#### Incremental Backup

To enable incremental backup, you need to update `BackupSchedule` and enable the method `archive-wal`.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
metadata:
  name: pg-cluster-postgresql-backup-schedule
  namespace: default
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
    enabled: true  # set to `true` to enable incremental backup
    retentionPeriod: 8d # set the retention period to your need
```

Once the `BackupSchedule` is updated, the incremental backup starts to work, and you can check the status of the backup with following command:

```bash
kubectl get backup -l app.kubernetes.io/instance=pg-cluster
```

And you will find one `Backup` named with suffix 'pg-cluster-postgresql-archive-wal' is created with the method `archive-wal`.

It will run continuously until you disable the method `archive-wal` in the `BackupSchedule`. And the valid time range of the backup will be recorded in the `Backup` resource:

```bash
kubectl get backup -l app.kubernetes.io/instance=pg-cluster -l dataprotection.kubeblocks.io/backup-type=Continuous  -oyaml | yq '.items[].status.timeRange'
```

#### [wal-g]

WAL-G is an archival restoration tool for PostgreSQL, MySQL/MariaDB, and MS SQL Server (beta for MongoDB and Redis).[^2]

##### Base Backup(basebackup-wal-g.yaml)

To create wal-g backup for the cluster, it is a multi-step process.

1. configure WAL-G on all PostgreSQL pods

```bash
kubectl apply -f examples/postgresql/config-wal-g.yaml
```

1. set `archive_command` to `wal-g wal-push %p`

```bash
kubectl apply -f examples/postgresql/backup-wal-g.yaml
```

1. you cannot do wal-g backup for a brand-new cluster, you need to insert some data before backup

1. create a backup

```bash
kubectl apply -f examples/postgresql/backup-wal-g.yaml
```

> [!Note]
> if there is horizontal scaling out new pods after step 2, you need to do config-wal-g again

### [Restore](restore.yaml)

To restore a new cluster from a Backup:

1. Get the list of accounts and their passwords from the backup:

```bash
kubectl get backup pg-cluster-pg-basebackup -ojsonpath='{.metadata.annotations.kubeblocks\.io/encrypted-system-accounts}'
```

1. Update `examples/postgresql/restore.yaml` and set fields quoated with `<>` to your own settings and apply it.

```bash
kubectl apply -f examples/postgresql/restore.yaml
```

### Expose

Expose a cluster with a new endpoint

#### [Enable](expose-enable.yaml)

```bash
kubectl apply -f examples/postgresql/expose-enable.yaml
```

#### [Disable](expose-disable.yaml)

```bash
kubectl apply -f examples/postgresql/expose-disable.yaml
```

### [Upgrade](upgrade.yaml)

Upgrade postgresql cluster to another version

```bash
kubectl apply -f examples/postgresql/upgrade.yaml
```

In this example, the cluster will be upgraded to version `14.8.0`.
You can check the available versions with following command:

```bash
kubectl get cmpv postgresql
```

And you can also use `kubectl edit` to upgrade the cluster:

```bash
kubectl edit cluster pg-cluster
```

And modify the `spec.componentSpecs.serviceVersion` field to the desired version.

You are suggested to check the compatibility of versions before upgrading, using command:

```bash
kubectl get cmpv postgresql -ojson | jq '.spec.compatibilityRules'
```
<details>
The expected output is like:
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
</details>

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster pg-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster pg-cluster
```

## References

[^1]: pg_basebackup, https://www.postgresql.org/docs/current/app-pgbasebackup.html
[^2]: wal-g https://github.com/wal-g/wal-g