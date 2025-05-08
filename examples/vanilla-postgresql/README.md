# vanilla-postgresql

Vanilla-PostgreSQL is compatible with the native PostgreSQL kernel, enabling it to quickly provide HA solutions for various variants based on the native PostgreSQL kernel.

## Features In KubeBlocks

### Lifecycle Management

| Topology | Horizontal scaling | Vertical scaling | Expand volume | Restart | Stop/Start | Configure | Expose | Switchover |
|----------|-------------------|------------------|---------------|---------|------------|-----------|---------|------------|
| vanilla-postgresql | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |

### Backup and Restore

| Feature | Method | Description |
|---------|---------|-------------|
| Full Backup | vanilla-pg-basebackup | uses `pg_basebackup`, a PostgreSQL utility to create a base backup |

### Versions

| Major Versions | Description       |
|---------------|-------------------|
| 12 | 12.15.0           |
| 14 | 14.7.0            |
| 15 | 15.7.0, 15.6.1-138 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Vanilla PostgreSQL Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

Create a Vanilla-PostgreSQL cluster with one primary and one secondary instance:

```bash
kubectl apply -f examples/vanilla-postgresql/cluster.yaml
```

And you will see the Vanilla-PostgreSQL cluster status goes `Running` after a while:

```bash
kubectl get -n demo cluster vanpg-cluster
```

and two pods are `Running` with roles `primary` and `secondary` separately. To check the roles of the pods, you can use following command:

```bash
# replace `vanpg-cluster` with your cluster name
kubectl get pod -n demo -l  app.kubernetes.io/instance=vanpg-cluster -L kubeblocks.io/role
```

If you want to create a Vanilla-PostgreSQL cluster of specified version, set the `spec.componentSpecs.serviceVersion` field in the yaml file before applying it:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  terminationPolicy: Delete
  clusterDef: vanilla-postgresql
  topology: vanilla-postgresql
  componentSpecs:
    - name: postgresql
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [12.15.0,14.7.0,15.7.0,15.6.1-138]
      serviceVersion: "14.7.0"
```

The list of supported versions can be found by following command:

```bash
kubectl get cmpv vanilla-postgresql
```

And the expected output is like:

```bash
NAME                 VERSIONS                                      STATUS      AGE
vanilla-postgresql   12.15.0,14.7.0,15.7.0,15.6.1-138               Available   Xd
```

### [Horizontal scaling](horizontalscale.yaml)

#### [Scale-out](scale-out.yaml)

Horizontal scaling out Vanilla-PostgreSQL cluster by adding ONE more replica:

```bash
kubectl apply -f examples/vanilla-postgresql/scale-out.yaml
```

After applying the operation, you will see a new pod created and the Vanilla-PostgreSQL cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `secondary`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe -n demo ops vanpg-scale-out
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in Vanilla-PostgreSQL cluster by deleting ONE replica:

```bash
kubectl apply -f examples/vanilla-postgresql/scale-in.yaml
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
      serviceVersion: "14.7.0"
      replicas: 2 # Update `replicas` to 1 for scaling in, and to 3 for scaling out
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/vanilla-postgresql/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/vanilla-postgresql/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/vanilla-postgresql/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/vanilla-postgresql/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/vanilla-postgresql/start.yaml
```

### Switchover

A switchover in database clusters is a planned operation that transfers the primary (leader) role from one database instance to another. The goal of a switchover is to ensure that the database cluster remains available and operational during the transition.

#### [Switchover without preferred candidates](switchover.yaml)

To perform a switchover without any preferred candidates, you can apply the following yaml file:

```bash
kubectl apply -f examples/vanilla-postgresql/switchover.yaml
```

<details>

<summary>Details</summary>

By applying this yaml file, KubeBlocks will perform a switchover operation defined in Vanilla-PostgreSQL's component definition, and you can check out the details in `componentdefinition.spec.lifecycleActions.switchover`.

You may get the switchover operation details with following command:

```bash
kubectl get cluster -n demo vanpg-cluster -ojson | jq '.spec.componentSpecs[0].componentDef' | xargs kubectl get cmpd -ojson | jq '.spec.lifecycleActions.switchover'
```

</details>

#### [Switchover with candidate specified](switchover-specified-instance.yaml)

Switchover a specified instance as the new primary or leader of the cluster

```bash
kubectl apply -f examples/vanilla-postgresql/switchover-specified-instance.yaml
```

You may need to update the `opsrequest.spec.switchover.instanceName` field to your desired `secondary` instance name.

Once this `opsrequest` is completed, you can check the status of the switchover operation and the roles of the pods to verify the switchover operation.

### [Reconfigure](configure.yaml)

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```bash
kubectl apply -f examples/vanilla-postgresql/configure.yaml
```

This example will change the `max_connections` to `200`.
> `max_connections` indicates maximum number of client connections allowed. It is a dynamic parameter, so the change will take effect without restarting the database.

```bash
kbcli cluster explain-config vanpg-cluster # kbcli is a command line tool to interact with KubeBlocks
```

### Backup

When create a backup for cluster, you need to create a BackupRepo first. You can refer to the "BackupRepo" section in the ```example/postgresql/README.md``` file to learn how to create a BackupRepo.

KubeBlocks now supports one backup method for Vanilla-PostgreSQL cluster, which is `vanilla-pg-basebackup`.
Other backup methods such as "wal-g" will be supported in the future.

You may find the supported backup methods in the `BackupPolicy` of the cluster, e.g. `vanpg-cluster-postgresql-backup-policy` in this case, and find how these methods will be scheduled in the `BackupSchedule` of the cluster e.g.`vanpg-cluster-postgresql-backup-schedule` in this case.

#### pg-basebackup

##### [Full Backup](backup-pg-basebasekup.yaml)

The method `vanilla-pg-basebackup` uses `pg_basebackup`,  a PostgreSQL utility to create a base backup

To create a base backup for the cluster, you can apply the following yaml file:

```bash
kubectl apply -f examples/vanilla-postgresql/backup-pg-basebasekup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -n demo -l app.kubernetes.io/instance=vanpg-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

Information, such as `path`, `timeRange` about the backup will be recorded into the `Backup` resource.

Alternatively, you can update the `BackupSchedule` to enable the method `vanilla-pg-basebackup` to schedule base backup periodically, will be elaborated in the following section.

### [Restore](restore.yaml)

To restore a new cluster from a Backup:

Get the list of accounts and their passwords from the backup:

```bash
kubectl get backup -n demo vanpg-cluster-pg-basebackup -ojsonpath='{.metadata.annotations.kubeblocks\.io/encrypted-system-accounts}'
```

Update `examples/vanilla-postgresql/restore.yaml` and set fields quoted with `<<ENCRYPTED-SYSTEM-ACCOUNTS>` to your own settings and apply it.

```bash
kubectl apply -f examples/vanilla-postgresql/restore.yaml
```

### Expose

Expose a cluster with a new endpoint

#### [Enable](expose-enable.yaml)

```bash
kubectl apply -f examples/vanilla-postgresql/expose-enable.yaml
```

#### [Disable](expose-disable.yaml)

```bash
kubectl apply -f examples/vanilla-postgresql/expose-disable.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo vanpg-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo vanpg-cluster
```
