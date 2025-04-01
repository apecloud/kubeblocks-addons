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

## Examples

### Create

Create a Vanilla-PostgreSQL cluster with one primary and one secondary instance:

```yaml
# cat examples/vanilla-postgresql/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: vanpg-cluster
  namespace: default
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
  clusterDef: vanilla-postgresql
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  # Valid options are: [replication]
  topology: vanilla-postgresql
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: postgresql
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [12.15.0,14.7.0,15.6.1-138,15.7.0]
      serviceVersion: "14.7.0"
      # Determines whether metrics exporter information is annotated on the
      # Component's headless Service.
      # Valid options are [true, false]
      disableExporter: false
      # Specifies Labels to override or add for underlying Pods, PVCs, Account & TLS
      # Secrets, Services Owned by Component.
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
kubectl apply -f examples/vanilla-postgresql/cluster.yaml
```

And you will see the Vanilla-PostgreSQL cluster status goes `Running` after a while:

```bash
kubectl get cluster vanpg-cluster
```

and two pods are `Running` with roles `primary` and `secondary` separately. To check the roles of the pods, you can use following command:

```bash
# replace `vanpg-cluster` with your cluster name
kubectl get pod -l  app.kubernetes.io/instance=vanpg-cluster -L kubeblocks.io/role -n default
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

### Horizontal scaling

#### Scale-out

Horizontal scaling out Vanilla-PostgreSQL cluster by adding ONE more replica:

```yaml
# cat examples/vanilla-postgresql/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-scale-out
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
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
kubectl apply -f examples/vanilla-postgresql/scale-out.yaml
```

After applying the operation, you will see a new pod created and the Vanilla-PostgreSQL cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `secondary`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe ops vanpg-scale-out
```

#### Scale-in

Horizontal scaling in Vanilla-PostgreSQL cluster by deleting ONE replica:

```yaml
# cat examples/vanilla-postgresql/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-scale-in
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
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

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/vanilla-postgresql/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-verticalscaling
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
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
kubectl apply -f examples/vanilla-postgresql/verticalscale.yaml
```

### Expand volume

Increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/vanilla-postgresql/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-volumeexpansion
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
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
kubectl apply -f examples/vanilla-postgresql/volumeexpand.yaml
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/vanilla-postgresql/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
    - componentName: postgresql
```

```bash
kubectl apply -f examples/vanilla-postgresql/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/vanilla-postgresql/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
  type: Stop

```

```bash
kubectl apply -f examples/vanilla-postgresql/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/vanilla-postgresql/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
  type: Start

```

```bash
kubectl apply -f examples/vanilla-postgresql/start.yaml
```

### Switchover

A switchover in database clusters is a planned operation that transfers the primary (leader) role from one database instance to another. The goal of a switchover is to ensure that the database cluster remains available and operational during the transition.

#### Switchover without preferred candidates

To perform a switchover without any preferred candidates, you can apply the following yaml file:

```yaml
# cat examples/vanilla-postgresql/switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-switchover
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: postgresql
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: vanpg-cluster-postgresql-0

```

```bash
kubectl apply -f examples/vanilla-postgresql/switchover.yaml
```

<details>

<summary>Details</summary>

By applying this yaml file, KubeBlocks will perform a switchover operation defined in Vanilla-PostgreSQL's component definition, and you can check out the details in `componentdefinition.spec.lifecycleActions.switchover`.

You may get the switchover operation details with following command:

```bash
kubectl get cluster vanpg-cluster -ojson | jq '.spec.componentSpecs[0].componentDef' | xargs kubectl get cmpd -ojson | jq '.spec.lifecycleActions.switchover'
```

</details>

#### Switchover with candidate specified

Switchover a specified instance as the new primary or leader of the cluster

```yaml
# cat examples/vanilla-postgresql/switchover-specified-instance.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-switchover-specify
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: postgresql
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: vanpg-cluster-postgresql-0
    # If CandidateName is specified, the role will be transferred to this instance.
    # The name must match one of the pods in the component.
    # Refer to ComponentDefinition's Swtichover lifecycle action for more details.
    candidateName: vanpg-cluster-postgresql-1

```

```bash
kubectl apply -f examples/vanilla-postgresql/switchover-specified-instance.yaml
```

You may need to update the `opsrequest.spec.switchover.instanceName` field to your desired `secondary` instance name.

Once this `opsrequest` is completed, you can check the status of the switchover operation and the roles of the pods to verify the switchover operation.

### Reconfigure

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```yaml
# cat examples/vanilla-postgresql/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-reconfiguring
  namespace: default
spec:
  # Specifies the type of this operation.
  type: Reconfiguring
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
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

##### Full Backup

The method `vanilla-pg-basebackup` uses `pg_basebackup`,  a PostgreSQL utility to create a base backup

To create a base backup for the cluster, you can apply the following yaml file:

```yaml
# cat examples/vanilla-postgresql/backup-pg-basebasekup.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: vanpg-cluster-pg-basebackup
  namespace: default
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - pg-basebackup
  # - volume-snapshot
  # - config-wal-g and wal-g
  # - archive-wal
  backupMethod: vanilla-pg-basebackup
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: vanpg-cluster-postgresql-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete

```

```bash
kubectl apply -f examples/vanilla-postgresql/backup-pg-basebasekup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -l app.kubernetes.io/instance=vanpg-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

Information, such as `path`, `timeRange` about the backup will be recorded into the `Backup` resource.

Alternatively, you can update the `BackupSchedule` to enable the method `vanilla-pg-basebackup` to schedule base backup periodically, will be elaborated in the following section.

### Restore

To restore a new cluster from a Backup:

Get the list of accounts and their passwords from the backup:

```bash
kubectl get backup vanpg-cluster-pg-basebackup -ojsonpath='{.metadata.annotations.kubeblocks\.io/encrypted-system-accounts}'
```

Update `examples/vanilla-postgresql/restore.yaml` and set fields quoted with `<<ENCRYPTED-SYSTEM-ACCOUNTS>` to your own settings and apply it.

```yaml
# cat examples/vanilla-postgresql/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: vanpg-restore
  namespace: default
  annotations:
    # NOTE: replace <ENCRYPTED-SYSTEM-ACCOUNTS> with the accounts info from you backup
    kubeblocks.io/restore-from-backup: '{"postgresql":{"encryptedSystemAccounts":"<ENCRYPTED-SYSTEM-ACCOUNTS>","name":"vanpg-cluster-pg-basebackup","namespace":"default","volumeRestorePolicy":"Parallel"}}'
spec:
  terminationPolicy: Delete
  clusterDef: vanilla-postgresql
  topology: vanilla-postgresql
  componentSpecs:
    - name: postgresql
      serviceVersion: "14.7.0"
      disableExporter: true
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
kubectl apply -f examples/vanilla-postgresql/restore.yaml
```

### Expose

Expose a cluster with a new endpoint

#### Enable

```yaml
# cat examples/vanilla-postgresql/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-expose-enable
  namespace: default
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
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
kubectl apply -f examples/vanilla-postgresql/expose-enable.yaml
```

#### Disable

```yaml
# cat examples/vanilla-postgresql/expose-disable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vanpg-expose-disable
  namespace: default
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: vanpg-cluster
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
kubectl apply -f examples/vanilla-postgresql/expose-disable.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster vanpg-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster vanpg-cluster
```
