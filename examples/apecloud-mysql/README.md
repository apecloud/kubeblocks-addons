# ApeCloud MySQL

ApeCloud MySQL is a database that is compatible with MySQL syntax and achieves high availability through the utilization of the **RAFT consensus protocol**. This example shows how it can be managed in Kubernetes with KubeBlocks.

Please refer to the ApeCloud MySQL Documentation[^1] for more information.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | Yes      |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Full Backup | xtrabackup   | uses `xtrabackup`, an open-source tool developed by Percona to perform full backups  |

### Versions

| Major Versions | Description |
|---------------|--------------|
| 8.0           | 8.0.30       |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- ApeCloud MySQL Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### [Create](cluster.yaml)

Create a ApeCloud-MySQL cluster with three replicas:

```yaml
# cat examples/apecloud-mysql/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: acmysql-cluster
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
  # The value must be `apecloud-mysql` to create a ApeCloud-MySQL Cluster
  clusterDef: apecloud-mysql
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  topology: apecloud-mysql
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: mysql
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [8.0.30]
      serviceVersion: "8.0.30"
      # Determines whether metrics exporter information is annotated on the
      # Component's headless Service.
      # Valid options are [true, false]
      disableExporter: false
      # Specifies the desired number of replicas in the Component
      # ApeCloud-MySQL prefers ODD numbers like [1, 3, 5, 7]
      replicas: 3
      # Specifies the resources required by the Component.
      resources:
        limits:
          cpu: '0.5'
          memory: 0.5Gi
        requests:
          cpu: '0.5'
          memory: 0.5Gi
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
kubectl apply -f examples/apecloud-mysql/cluster.yaml
```

And you will see the ApeCloud-MySQL cluster status goes `Running` after a while:

```bash
kubectl get cluster acmysql-cluster
```

and three pods are `Running` with roles `leader`,  `follower` and `follower` separately. To check the roles of the pods, you can use following command:

```bash
# replace `acmysql-cluster` with your cluster name
kubectl get po -l  app.kubernetes.io/instance=acmysql-cluster -L kubeblocks.io/role -n demo
```

If you want to create a cluster of specified version, set the `spec.componentSpecs.serviceVersion` field in the yaml file before applying it:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
spec:
  componentSpecs:
    - name: mysql
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [8.0.30]
      serviceVersion: "8.0.30" # more ApeCloud-MySQL versions will be supported in the future
```

The list of supported versions can be found by following command:

```bash
kubectl get cmpv apecloud-mysql
```

### Horizontal scaling

> [!IMPORTANT]
> As per the ApeCloud MySQL documentation, the number of Raft replicas should be odd to avoid split-brain scenarios.
> Make sure the number of ApeCloud MySQL replicas, is always odd after Horizontal Scaling.

#### [Scale-out](scale-out.yaml)

Horizontal scaling out ApeCloud-MySQL cluster by adding ONE more replica:

```yaml
# cat examples/apecloud-mysql/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: mysql
    # Specifies the replica changes for scaling out components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/apecloud-mysql/scale-out.yaml
```

After applying the operation, you will see a new pod created and the ApeCloud-MySQL cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `follower`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe ops acmysql-scale-out
```

> [!IMPORTANT]
> On scaling out, the new replica will be added as a follower, and KubeBlocks will clone data from the leader to the new follower before the replica starts as defined.

#### [Scale-in](scale-in.yaml)

Horizontal scaling in ApeCloud-MySQL cluster by deleting ONE replica:

```yaml
# cat examples/apecloud-mysql/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: mysql
    # Specifies the replica changes for scaling out components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/apecloud-mysql/scale-in.yaml
```

> [!IMPORTANT]
> On scaling in, the replica will be forgetton from the cluster's Raft group before it is deleted.

#### [Set Specified Replicas Offline](scale-in-specified-instance.yaml)

There are cases where you want to set a specified replica offline, when it is problematic or you want to do some maintenance work on it. You can use the `onlineInstancesToOffline` field in the `spec.horizontalScaling.scaleIn` section to specify the instance names that need to be taken offline.

```yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
spec:
  horizontalScaling:
  - componentName: mysql
    # Specifies the replica changes for scaling out components
    scaleIn:
      onlineInstancesToOffline:
        - 'acmysql-cluster-mysql-1'  # Specifies the instance names that need to be taken offline
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
spec:
  componentSpecs:
    - name: apecloud-mysql
      replicas: 3 # decrease `replicas` for scaling in, and increase for scaling out
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```yaml
# cat examples/apecloud-mysql/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: mysql
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/apecloud-mysql/verticalscale.yaml
```

You will observe that the `follower` pods are recreated first, followed by the `leader` pod, to ensure the availability of the cluster.

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
spec:
  componentSpecs:
    - name: mysql
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

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created. It is introduced in Kubernetes v1.11 and goes GA in Kubernetes v1.24. It allows Kubernetes users to simply edit their PersistentVolumeClaim objects without requiring any downtime at all if possible.

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

To increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/apecloud-mysql/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: mysql
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/apecloud-mysql/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=acmysql-cluster -n demo
```

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
spec:
  componentSpecs:
    - name: mysql
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

```yaml
# cat examples/apecloud-mysql/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: mysql

```

```bash
kubectl apply -f examples/apecloud-mysql/restart.yaml
```

> [!NOTE]
> All follower pods will be restarted first, followed by the leader pod, to ensure the availability of the cluster.

### [Stop](stop.yaml)

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```yaml
# cat examples/apecloud-mysql/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  type: Stop

```

```bash
kubectl apply -f examples/apecloud-mysql/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
spec:
  componentSpecs:
    - name: mysql
      stop: true  # set stop `true` to stop the component
      replicas: 3
```

### [Start](start.yaml)

Start the stopped cluster

```yaml
# cat examples/apecloud-mysql/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  type: Start

```

```bash
kubectl apply -f examples/apecloud-mysql/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
spec:
  componentSpecs:
    - name: mysql
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 3
```

### Switchover

A switchover in database clusters is a planned operation that transfers the primary (leader) role from one database instance to another. The goal of a switchover is to ensure that the database cluster remains available and operational during the transition.

<details>

By applying this yaml file, KubeBlocks will perform a switchover operation defined in component definition, and you can checkout the details in `componentdefinition.spec.lifecycleActions.switchover`.

</details>

#### [Switchover without preferred candidates](switchover.yaml)

Switchover a specified instance as the new primary or leader of the cluster

```yaml
# cat examples/apecloud-mysql/switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-switchover
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: mysql
    # Specifies the instance to become the primary or leader during a switchover operation. The value of `instanceName` can be either:
    # - "*" (wildcard value): - Indicates no specific instance is designated as the primary or leader.
    # - A valid instance name (pod name)
    instanceName: '*'

```

```bash
kubectl apply -f examples/apecloud-mysql/switchover.yaml
```

#### [Switchover-specified-instance](switchover-specified-instance.yaml)

Switchover a specified instance as the new primary or leader of the cluster

```yaml
# cat examples/apecloud-mysql/switchover-specified-instance.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-switchover-specify
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: mysql
    # Specifies the instance to become the primary or leader during a switchover operation. The value of `instanceName` can be either:
    # - "*" (wildcard value): - Indicates no specific instance is designated as the primary or leader.
    # - A valid instance name (pod name)
    instanceName: acmysql-cluster-mysql-2

```

```bash
kubectl apply -f examples/apecloud-mysql/switchover-specified-instance.yaml
```

You may need to update the `opsrequest.spec.switchover.instanceName` field to your desired instance name.

### [Reconfigure](configure.yaml)

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```yaml
# cat examples/apecloud-mysql/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-reconfiguring
  namespace: demo
spec:
  # Specifies the type of this operation.
  type: Reconfiguring
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: mysql
   # Contains a list of ConfigurationItem objects, specifying the Component's configuration template name, upgrade policy, and parameter key-value pairs to be updated.
    configurations:
      # Sets the parameters to be updated. It should contain at least one item.
      # The keys are merged and retained during patch operations.
    - keys:
        # Represents the unique identifier for the ConfigMap.
      - key: my.cnf
        # Defines a list of key-value pairs for a single configuration file.
        # These parameters are used to update the specified configuration settings.
        parameters:
          # Represents the name of the parameter that is to be updated.
        - key: innodb_buffer_pool_size
          # Represents the parameter values that are to be updated.
          # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
          value: 512M
        - key: max_connections
          value: '600'
      # Specifies the name of the configuration template.
      name: mysql-consensusset-config
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0

```

```bash
kubectl apply -f examples/apecloud-mysql/configure.yaml
```

This example will change the `max_connections` to `600` and `innodb_buffer_pool_size` to `512M` for the specified component.

You may log into the MySQL instance to check the configuration changes:

```sql
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
```

### [Backup](backup.yaml)

> [!IMPORTANT] Before you start, please create a `BackupRepo` to store the backup data. Refer to [BackupRepo](../docs/create-backuprepo.md) for more details.

You may find the supported backup methods in the `BackupPolicy` of the cluster, e.g. `acmysql-cluster-mysql-backup-policy` in this case, and find how these methods will be scheduled in the `BackupSchedule` of the cluster, e.g.. `acmysql-cluster-mysql-backup-schedule` in this case.

To create a full backup, using `xtrabackup`, for the cluster:

```yaml
# cat examples/apecloud-mysql/backup.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: acmysql-cluster-backup
  namespace: demo
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - xtrabackup
  # - volume-snapshot
  backupMethod: xtrabackup
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: acmysql-cluster-mysql-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete

```

```bash
kubectl apply -f examples/apecloud-mysql/backup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -l app.kubernetes.io/instance=acmysql-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

Information, such as `path`, `timeRange` about the backup will be recorded into the `Backup` resource.

Alternatively, you can update the `BackupSchedule` to enable the method `xtrabackup` to schedule base backup periodically.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
metadata:
  name: acmysql-cluster-mysql-backup-schedule
  namespace: demo
spec:
  backupPolicyName: acmysql-cluster-mysql-backup-policy
  schedules:
  - backupMethod: xtrabackup
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
```

### [Restore](restore.yaml)

To restore a new cluster from a Backup:

1. Get the list of accounts and their passwords from the backup:

```bash
kubectl get backup acmysql-cluster-backup -ojsonpath='{.metadata.annotations.kubeblocks\.io/encrypted-system-accounts}'
```

1. Update `examples/apecloud-mysql/restore.yaml` and set placeholder `<ENCRYPTED-SYSTEM-ACCOUNTS>` with your own settings and apply it.

```yaml
# cat examples/apecloud-mysql/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: acmysql-cluster-restore
  namespace: demo
  annotations:
    kubeblocks.io/restore-from-backup: '{"mysql":{"encryptedSystemAccounts":"<ENCRYPTED-SYSTEM-ACCOUNTS>","name":"acmysql-cluster-backup","namespace":"default","volumeRestorePolicy":"Parallel"}}'
spec:
  terminationPolicy: Delete
  clusterDef: apecloud-mysql
  topology: apecloud-mysql
  componentSpecs:
    - name: mysql
      serviceVersion: "8.0.30"
      disableExporter: false
      replicas: 3
      resources:
        limits:
          cpu: '0.5'
          memory: 0.5Gi
        requests:
          cpu: '0.5'
          memory: 0.5Gi
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
kubectl apply -f examples/apecloud-mysql/restore.yaml
```

### Expose

Expose a cluster with a new endpoint

#### [Enable](expose-enable.yaml)

```yaml
# cat examples/apecloud-mysql/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-expose-enable
  namespace: demo
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: mysql
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
      roleSelector: leader
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Enable
```

```bash
kubectl apply -f examples/apecloud-mysql/expose-enable.yaml
```

#### [Disable](expose-disable.yaml)

```yaml
# cat examples/apecloud-mysql/expose-disable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-expose-disable
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: mysql
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      roleSelector: leader
      serviceType: LoadBalancer
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Disable
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Expose

```

```bash
kubectl apply -f examples/apecloud-mysql/expose-disable.yaml
```

#### Expose SVC using Cluster API

Alternatively, you may expose service by updating `spec.services`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
spec:
  # append service to the list
  services:
    # add annotation for cloud loadbalancer if
    # services.spec.type is LoadBalancer
    # here we use annotation for alibaba cloud for example
  - annotations:
      service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: internet
    componentSelector: mysql
    name: acmysql-vpc
    serviceName: acmysql-vpc
    # optional. it specify defined role as selector for the service.
    # onece specified, service will select and route traffic to Pods with the label
    # "kubeblocks.io/role=<specified-role-name>".
    # valid options are: [leader, follower] for ApeCloud-MySQL
    roleSelector: leader
    spec:  # defines the behavior of a K8s service.
      ipFamilyPolicy: PreferDualStack
      ports:
      - name: tcp-mysql
        # port to expose
        port: 3306
        protocol: TCP
        targetPort: mysql
      # Determines how the Service is exposed. Defaults to 'ClusterIP'.
      # Valid options are [`ClusterIP`, `NodePort`, and `LoadBalancer`]
      type: LoadBalancer
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

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

##### Step 1. Query ScrapePath and ScrapePort

You can retrieve the `scrapePath` and `scrapePort` from pod's exporter container.

```bash
kubectl get po acmysql-cluster-mysql-0 -oyaml | yq '.spec.containers[] | select(.name=="mysql-exporter") | .ports '
```

And the expected output is like:

```text
- containerPort: 9104
  name: http-metrics
  protocol: TCP
```

##### Step 2. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/apecloud-mysql/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: acmysql-cluster-pod-monitor
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
      app.kubernetes.io/instance: acmysql-cluster
      apps.kubeblocks.io/component-name: mysql
```

```bash
kubectl apply -f examples/apecloud-mysql/pod-monitor.yaml
```

##### Step 3. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard.

KubeBlocks provides a Grafana dashboard for monitoring the ApeCloud MySQL cluster. You can find it at [ApeCloud MySQL Dashboard](https://github.com/apecloud/kubeblocks-addons/tree/main/addons/apecloud-mysql).

> [!Note]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster acmysql-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster acmysql-cluster
```
<!--
## SmartEngine

SmartEngine is an OLTP storage engine based on LSM-Tree architecture and supports complete ACID transaction constraints.

### [Enable](smartengine-enable.yaml)

```yaml
# cat examples/apecloud-mysql/smartengine-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-enable-smartengine
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: mysql
   # Contains a list of ConfigurationItem objects, specifying the Component's configuration template name, upgrade policy, and parameter key-value pairs to be updated.
    configurations:
      # Sets the parameters to be updated. It should contain at least one item.
      # The keys are merged and retained during patch operations.
      - keys:
          # Represents the unique identifier for the ConfigMap.
          - key: my.cnf
            # Defines a list of key-value pairs for a single configuration file.
            # These parameters are used to update the specified configuration settings.
            parameters:
              # Represents the name of the parameter that is to be updated.
              - key: loose_smartengine
                # Represents the parameter values that are to be updated.
                # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
                value: "ON"
              - key: binlog_format
                value: "ROW"
              - key: default_storage_engine
                value: "smartengine"
        # Specifies the name of the configuration template.
        name: mysql-consensusset-config
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring

```

```bash
kubectl apply -f examples/apecloud-mysql/smartengine-enable.yaml
```

### [Disable](smartengine-disable.yaml)

```yaml
# cat examples/apecloud-mysql/smartengine-disable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-disable-smartengine
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: mysql
   # Contains a list of ConfigurationItem objects, specifying the Component's configuration template name, upgrade policy, and parameter key-value pairs to be updated.
    configurations:
      # Sets the parameters to be updated. It should contain at least one item.
      # The keys are merged and retained during patch operations.
      - keys:
          # Represents the unique identifier for the ConfigMap.
          - key: my.cnf
            # Defines a list of key-value pairs for a single configuration file.
            # These parameters are used to update the specified configuration settings.
            parameters:
              # Represents the name of the parameter that is to be updated.
              - key: loose_smartengine
                # Represents the parameter values that are to be updated.
                # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
                value: "OFF"
              - key: binlog_format
                value: "MIXED"
              - key: default_storage_engine
                value: "InnoDB"
        # Specifies the name of the configuration template.
        name: mysql-consensusset-config
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring

```

```bash
kubectl apply -f examples/apecloud-mysql/smartengine-disable.yaml
```
``` -->

## ApeCloud MySQL Proxy

ApeCloud MySQL Proxy[^2] is a database proxy designed to be highly compatible with MySQL.
It supports the MySQL wire protocol, read-write splitting without stale reads, connection pooling, and transparent failover.

### [Create Cluster with Proxy](cluster-proxy.yaml)

```yaml
# cat examples/apecloud-mysql/cluster-proxy.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: acmysql-proxy-cluster
  namespace: demo
spec:
  terminationPolicy: Delete
  clusterDef: apecloud-mysql
  topology: apecloud-mysql-proxy-etcd
  componentSpecs:
    - name: mysql
      serviceVersion: 8.0.30
      env:
        - name: KB_PROXY_ENABLED
          value: "on"
      replicas: 3
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
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
    - name: wescale-ctrl
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
      replicas: 1
      resources:
        limits:
          cpu: 500m
          memory: 128Mi
    - name: wescale
      replicas: 1
      resources:
        requests:
          cpu: "0.5"
          memory: 500Mi
        limits:
          cpu: "0.5"
          memory: 500Mi
    - name: etcd
      serviceVersion: "3.5.6"
      replicas: 3
      resources:
        requests:
          cpu: 500m
          memory: 500Mi
        limits:
          cpu: 500m
          memory: 500Mi
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
kubectl apply -f examples/apecloud-mysql/cluster-proxy.yaml
```

It creates a ApeCloud-MySQL component of 3 replicas, a wescale controller of 1 replica, a wescale of 1 replica, and an ETCD comonent with 3 replicas.

To connect to the ApeCloud MySQL Proxy, you can:

- port forward the service to your local machine:

```bash
# kubectl port-forward svc/<clusterName>-wescale 3306:3306
kubectl port-forward svc/acmysql-proxy-cluster-wescale 15306:15306
```

- login to with the following command:

```bash
mysql -h<endpoint> -P 15306 -u<userName> -p<password>
```

You may scale wescale and ETCD components as needed.

## Appendix

### How to Connect to ApesCloud MySQL

To connect to the ApeCloud MySQL cluster, you can:

- port forward the MySQL service to your local machine:

```bash
kubectl port-forward svc/<clusterName>-mysql 3306:3306
```

- or expose the MySQL service to the internet, as mentioned in the [Expose](#expose) section.

Then you can connect to the MySQL cluster with the following command:

```bash
mysql -h <endpoint> -P 3306 -u <userName> -p <password>
```

and credentials can be found in the `secret` resource:

```bash
kubectl get secret <clusterName>-mysql-account-root -ojsonpath='{.data.username}' | base64 -d
kubectl get secret <clusterName>-mysql-account-root -ojsonpath='{.data.password}' | base64 -d
```

### How to Check the Status of ApeCloud MySQL

You can check the status of the ApeCloud MySQL cluster with the following command:

```bash
mysql > select * from information_schema.WESQL_CLUSTER_GLOBAL;
mysql > select * from information_schema.WESQL_CLUSTER_HEALTH;
```

## References

[^1]: ApeCloud MySQL,https://kubeblocks.io/docs/preview/user_docs/kubeblocks-for-apecloud-mysql/apecloud-mysql-intro
