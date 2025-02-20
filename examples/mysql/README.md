# Mysql

MySQL is a widely used, open-source relational database management system (RDBMS)


## Features In KubeBlocks

### Lifecycle Management

|   Topology       | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| replication     | Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | Yes      |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Full Backup | xtrabackup   | uses `xtrabackup`, an open-source tool developed by Percona to perform full backups  |

### Versions

| Major Versions | Description |
|---------------|--------------|
| 5.7 | 5.7.44     |
| 8.0 | 8.0.30,8.0.31,8.0.32,8.0.33,8.0.34,8.0.35,8.0.36,8.0.37,8.0.38,8.0.39 |
| 8.4 | 8.4.0,8.4.1,8.4.2|

## Prerequisites

This example assumes that you have a Kubernetes cluster installed and running, and that you have installed the kubectl command line tool and helm somewhere in your path. Please see the [getting started](https://kubernetes.io/docs/setup/)  and [Installing Helm](https://helm.sh/docs/intro/install/) for installation instructions for your platform.

Also, this example requires KubeBlocks installed and running. Here is the steps to install KubeBlocks, please replace "`$kb_version`" with the version you want to use.

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

### Enable MySQL Add-on

If MySQL Addon is not enabled, you can enable it by following the steps below.

#### Using Helm

```bash
# Add Helm repo
helm repo add kubeblocks-addons https://apecloud.github.io/helm-charts
# If github is not accessible or very slow for you, please use following repo instead
helm repo add kubeblocks-addons https://jihulab.com/api/v4/projects/150246/packages/helm/stable
# Update helm repo
helm repo update
# Search versions of the Addon
helm search repo kubeblocks/mysql --versions
# Install the version you want (replace $version with the one you need)
helm upgrade -i mysql kubeblocks-addons/mysql --version $version -n kb-system
```

#### Using kbcli

```bash
# Search Addon
kbcli addon search mysql
# Install Addon with the version you want, replace $version with the one you need
kbcli addon install mysql --version $version
# To upgrade the addon, you can use the following command
kbcli addon upgrade mysql --version $version
```

## Examples

### Create

#### [Cluster with built-in HA Manager](cluster.yaml)

Create a MySQL cluster with two replicas that uses the built-in HA manager

```yaml
# cat examples/mysql/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mysql-cluster
  namespace: demo
spec:
  # Specifies the behavior when a Cluster is deleted.
  # Valid options are: [DoNotTerminate, Delete, WipeOut] (`Halt` is deprecated since KB 0.9)
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: mysql
      # Specifies the ComponentDefinition custom resource (CR) that defines the
      # Component's characteristics and behavior.
      # Supports three different ways to specify the ComponentDefinition:
      # - the regular expression - recommended
      # - the full name - recommended
      # - the name prefix
      componentDef: "mysql-8.0"  # match all CMPD named with 'mysql-8.0-'
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # When componentDef is "mysql-8.0",
      # Valid options are: [8.0.30,8.0.31,8.0.32,8.0.33,8.0.34,8.0.35,8.0.36,8.0.37,8.0.38,8.0.39]
      serviceVersion: 8.0.35
      # Determines whether metrics exporter information is annotated on the
      # Component's headless Service.
      # Valid options are [true, false]
      disableExporter: false
      # Specifies the desired number of replicas in the Component
      replicas: 2
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
kubectl apply -f examples/mysql/cluster.yaml
```

If you want to create a cluster of specified version, set the `spec.componentSpecs.serviceVersion` field in the yaml file before applying it:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mysql-cluster
  namespace: demo
spec:
  componentSpecs:
    - name: mysql
      componentDef: "mysql-8.0"  # match all CMPD named with 'mysql-8.0-'
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # When componentDef is "mysql-8.0",
      # Valid options are: [8.0.30,8.0.31,8.0.32,8.0.33,8.0.34,8.0.35,8.0.36,8.0.37,8.0.38,8.0.39]
      serviceVersion: 8.0.35
```

The list of supported versions can be found by following command:

```bash
kubectl get cmpv mysql
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out MySQL cluster by adding ONE more replica:

```yaml
# cat examples/mysql/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: mysql
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/mysql/scale-out.yaml
```

After applying the operation, you will see a new pod created and the MySQL cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `secondary`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe ops mysql-scale-out
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in MySQL cluster by deleting ONE replica:

```yaml
# cat examples/mysql/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: mysql
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/mysql/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mysql-cluster
  namespace: demo
spec:
  componentSpecs:
    - name: mysql
      replicas: 2 # decrease `replicas` for scaling in, and increase for scaling out
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```yaml
# cat examples/mysql/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
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
kubectl apply -f examples/mysql/verticalscale.yaml
```

You will observe that the `secondary` pods are recreated first, followed by the `primary` pod, to ensure the availability of the cluster.

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mysql-cluster
  namespace: demo
spec:
  componentSpecs:
    - name: mysql
      replicas: 2
      resources:
        requests:
          cpu: "1"       # Update the resources to your need.
          memory: "2Gi"  # Update the resources to your need.
        limits:
          cpu: "2"       # Update the resources to your need.
          memory: "4Gi"  # Update the resources to your need.
```

### [Expand volume](volumeexpand.yaml)

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created. It is introduced in Kubernetes v1.11 and goes GA in Kubernetes v1.24. It allows Kubernetes users to simply edit their PersistentVolumeClaim objects without requiring any downtime at all if possible[^4].

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

To increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/mysql/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
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
kubectl apply -f examples/mysql/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=mysql-cluster -n demo
```

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mysql-cluster
  namespace: demo
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
# cat examples/mysql/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: mysql

```

```bash
kubectl apply -f examples/mysql/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```yaml
# cat examples/mysql/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
  type: Stop

```

```bash
kubectl apply -f examples/mysql/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mysql-cluster
  namespace: demo
spec:
  componentSpecs:
    - name: mysql
      stop: true  # set stop `true` to stop the component
      replicas: 2
```

### [Start](start.yaml)

Start the stopped cluster

```yaml
# cat examples/mysql/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
  type: Start

```

```bash
kubectl apply -f examples/mysql/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mysql-cluster
  namespace: demo
spec:
  componentSpecs:
    - name: mysql
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 2
```

### Switchover

A switchover in database clusters is a planned operation that transfers the primary (leader) role from one database instance to another. The goal of a switchover is to ensure that the database cluster remains available and operational during the transition.

### [Switchover-specified-instance](switchover-specified-instance.yaml)

Switchover a specified instance as the new primary or leader of the cluster

```yaml
# cat examples/mysql/switchover-specified-instance.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-switchover-specify
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: mysql
    # Specifies the instance to become the primary or leader during a switchover operation. The value of `instanceName` can be either:
    # - "*" (wildcard value): - Indicates no specific instance is designated as the primary or leader.
    # - A valid instance name (pod name)
    instanceName: mysql-cluster-mysql-1

```

```bash
kubectl apply -f examples/mysql/switchover-specified-instance.yaml
```

### [Configure](configure.yaml)

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```yaml
# cat examples/mysql/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-reconfiguring
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
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
        - key: binlog_expire_logs_seconds
          # Represents the parameter values that are to be updated.
          # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
          value: '691200'
      # Specifies the name of the configuration template.
      name: mysql-replication-config
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring

```

```bash
kubectl apply -f examples/mysql/configure.yaml
```

This example will change the `binlog_expire_logs_seconds` to `691200`. To verify the changes, You may log into the MySQL instance to check the configuration changes:

```sql
SHOW VARIABLES LIKE 'binlog_expire_logs_seconds';
```

### [BackupRepo](backuprepo.yaml)

BackupRepo is the storage repository for backup data. Before creating a BackupRepo, you need to create a secret to save the access key of the backup repository

```bash
# Create a secret to save the access key
kubectl create secret generic <credential-for-backuprepo>\
  --from-literal=accessKeyId=<ACCESS KEY> \
  --from-literal=secretAccessKey=<SECRET KEY> \
  -n kb-system
```

Update `examples/mysql/backuprepo.yaml` and set fields quoted with `<>` to your own settings and apply it.

```yaml
# cat examples/mysql/backuprepo.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupRepo
metadata:
  name: s3-repo
  annotations:
    dataprotection.kubeblocks.io/is-default-repo: 'true'
spec:
  # Specifies the name of the `StorageProvider` used by this backup repository.
  # Currently, KubeBlocks supports configuring various object storage services as backup repositories
  # - s3 (Amazon Simple Storage Service)
  # - oss (Alibaba Cloud Object Storage Service)
  # - cos (Tencent Cloud Object Storage)
  # - gcs (Google Cloud Storage)
  # - obs (Huawei Cloud Object Storage)
  # - minio, and other S3-compatible services.
  storageProviderRef: s3
  # Specifies the access method of the backup repository.
  # - Tool
  # - Mount
  accessMethod: Tool
  # Specifies reclaim policy of the PV created by this backup repository.
  pvReclaimPolicy: Retain
  # Specifies the capacity of the PVC created by this backup repository.
  volumeCapacity: 100Gi
  # Stores the non-secret configuration parameters for the `StorageProvider`.
  config:
    bucket: <storage-provider-bucket-name>
    endpoint: ''
    mountOptions: --memory-limit 1000 --dir-mode 0777 --file-mode 0666
    region: <storage-provider-region-name>
  # References to the secret that holds the credentials for the `StorageProvider`.
  credential:
    # name is unique within a namespace to reference a secret resource.
    name: s3-credential-for-backuprepo
    # namespace defines the space within which the secret name must be unique.
    namespace: kb-system

```

```bash
kubectl apply -f examples/mysql/backuprepo.yaml
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

### [Backup](backup.yaml)

You may find the supported backup methods in the `BackupPolicy` of the cluster, e.g. `mysql-cluster-mysql-backup-policy` in this case, and find how these methods will be scheduled in the `BackupSchedule` of the cluster, e.g.. `mysql-cluster-mysql-backup-schedule` in this case.

To create a full backup, using `xtrabackup`, for the cluster:

```yaml
# cat examples/mysql/backup.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: mysql-cluster-backup
  namespace: demo
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - xtrabackup
  # - volume-snapshot
  backupMethod: xtrabackup
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: mysql-cluster-mysql-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete

```

```bash
kubectl apply -f examples/mysql/backup.yaml
```

### [Restore](restore.yaml)

To restore a new cluster from a Backup:

1. Get the list of accounts and their passwords from the backup:

```bash
kubectl get backup mysql-cluster-backup -ojsonpath='{.metadata.annotations.kubeblocks\.io/encrypted-system-accounts}'
```

1. Update `examples/mysql/restore.yaml` and set placeholder `<ENCRYPTED-SYSTEM-ACCOUNTS>` with your own settings and apply it.

```yaml
# cat examples/mysql/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mysql-cluster-restore
  namespace: demo
  annotations:
    kubeblocks.io/restore-from-backup: '{"mysql":{"encryptedSystemAccounts":"<ENCRYPTED-SYSTEM-ACCOUNTS>","name":"mysql-cluster-backup","namespace":"default","volumeRestorePolicy":"Parallel"}}'
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: mysql
      componentDef: "mysql-8.0"  # match all CMPD named with 'mysql-8.0-'
      serviceVersion: 8.0.35
      disableExporter: false
      replicas: 2
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
kubectl apply -f examples/mysql/restore.yaml
```

### Expose

Expose a cluster with a new endpoint

#### [Enable](expose-enable.yaml)

```yaml
# cat examples/mysql/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-expose-enable
  namespace: demo
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
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
      roleSelector: primary
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Enable
```

```bash
kubectl apply -f examples/mysql/expose-enable.yaml
```

#### [Disable](expose-disable.yaml)

```yaml
# cat examples/mysql/expose-disable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-expose-disable
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: mysql
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      roleSelector: primary
      serviceType: LoadBalancer
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Disable
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Expose

```

```bash
kubectl apply -f examples/mysql/expose-disable.yaml
```

#### Expose SVC using Cluster API

Alternatively, you may expose service by updating `spec.services`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mysql-cluster
  namespace: demo
spec:
  # append service to the list
  services:
    # add annotation for cloud loadbalancer if
    # services.spec.type is LoadBalancer
    # here we use annotation for alibaba cloud for example
  - annotations:
      service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: internet
    componentSelector: mysql
    name: mysql-vpc
    serviceName: mysql-vpc
    # optional. it specify defined role as selector for the service.
    # onece specified, service will select and route traffic to Pods with the label
    # "kubeblocks.io/role=<specified-role-name>".
    # valid options are: [primary, secondary] for MySQL
    roleSelector: primary
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
  componentSpecs:
    - name: mysql
      replicas: 2
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

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

##### Step 1. Query ScrapePath and ScrapePort

You can retrieve the `scrapePath` and `scrapePort` from pod's exporter container.

```bash
kubectl get po mysql-cluster-mysql-0 -oyaml | yq '.spec.containers[] | select(.name=="mysql-exporter") | .ports '
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
# cat examples/mysql/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: mysql-cluster-pod-monitor
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
      app.kubernetes.io/instance: mysql-cluster
      apps.kubeblocks.io/component-name: mysql
```

```bash
kubectl apply -f examples/mysql/pod-monitor.yaml
```

##### Step 3. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard.

> [!Note]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster mysql-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster mysql-cluster
```

### Manage MySQL Cluster using Orchestrator

KubeBlocks provides you an alternative to  create a MySQL cluster that uses the Orchestrator[^1] HA manager

- Step 1. Install Orchestrator Addon

Before creating the cluster with Orchestrator, make sure you have installed the Orchestrator addon.

```bash

```


- Step 2. Create Orchestrator Cluster

Create an Orchestrator cluster with three replicas;

```yaml
# cat examples/mysql/orchestrator.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: myorc
  namespace: demo
spec:
  clusterDef: orchestrator
  topology: raft
  terminationPolicy: Delete
  services:
    - name: orchestrator
      componentSelector: orchestrator
      spec:
        ports:
          - name: orc-http
            port: 80
  componentSpecs:
    - name: orchestrator
      disableExporter: true
      replicas: 3
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
        requests:
          cpu: "1"
          memory: "1Gi"
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi

```

```bash
kubectl apply -f examples/mysql/orchestrator.yaml
```

- Step 3. Create a MySQL Cluster

```yaml
# cat examples/mysql/cluster-orc.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mysql-cluster
  namespace: demo
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: mysql
      componentDef: mysql-orc-8.0 # use componentDef: mysql-orc-8.0
      disableExporter: true
      serviceVersion: "8.0.35"
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
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
      serviceRefs:
        - name: orchestrator
          namespace: demo # set to your orchestrator cluster namespace
          clusterServiceSelector:
            cluster:  myorc  # set to your orchestrator cluster name
            service:
              component: orchestrator
              service: orchestrator
              port:  orc-http
            credential:
              component: orchestrator
              name: orchestrator
```

```bash
kubectl apply -f examples/mysql/cluster-orc.yaml
```

#### Switchover(switchover-orc.yaml)

You can switchover a specified instance as the new primary or leader of the cluster

```yaml
# cat examples/mysql/switchover-orc.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mysql-switchover
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mysql-cluster
  type: Custom
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  custom:
    components:
      - componentName: mysql
        parameters:
          - name: candidate
            value: mysql-cluster-mysql-1
    opsDefinitionName: mysql-orc-switchover # predefined opsdefinition for switchover
```

```bash
kubectl apply -f examples/mysql/switchover-orc.yaml
```

## References

