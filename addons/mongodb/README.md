# MongoDB

MongoDB is a document database designed for ease of application development and scaling

## Features In KubeBlocks

### Lifecycle Management

| Topology | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|----------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| replica set | Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | Yes      |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Full Backup | dump   | uses `mongodump`, a MongoDB utility used to create a binary export of the contents of a database  |
| Full Backup | datafile | backup the data files of the database |

### Versions

| Major Versions | Description |
|---------------|--------------|
| 4.0 | 4.0.28,4.2.24,4.4.29 |
| 5.0 | 5.0.28 |
| 6.0 | 6.0.16 |
| 7.0 | 7.0.12 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- MongoDB Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### Create

Create a MongoDB replicaset cluster with 1 primary replica and 2 secondary replicas:

```yaml
# cat examples/mongodb/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mongo-cluster
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
  # The value must be `mongodb` to create a MongoDB Cluster
  clusterDef: mongodb
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  # Valid options are [replicaset]
  topology: replicaset
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: mongodb
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [4.0.28,4.2.24,4.4.29,5.0.28,6.0.16,7.0.1]
      serviceVersion: "6.0.16"
      # Specifies the desired number of replicas in the Component
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
kubectl apply -f examples/mongodb/cluster.yaml
```

To check the roles of the pods, you can use following command:

```bash
# replace `mongo-cluster` with your cluster name
kubectl get po -l  app.kubernetes.io/instance=mongo-cluster -L kubeblocks.io/role -n default
```

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
      # Valid options are: [4.0.28,4.2.24,4.4.29,5.0.28,6.0.16,7.0.1]
      serviceVersion: "7.0.1"
```

The list of supported versions can be found by following command:

```bash
kubectl get cmpv mongodb
```

#### What is MongoDB Replica Set?

A MongoDB replica set[^1] is a group of MongoDB servers that maintain the same dataset, providing high availability and data redundancy. Replica sets are the foundation of MongoDB's fault tolerance and data reliability. By replicating data across multiple nodes, MongoDB ensures that if one server fails, another can take over seamlessly without affecting the application's availability.

In a replica set, there are typically three types of nodes:

- Primary Node: Handles all write operations and serves read requests by default.
- Secondary Nodes: Maintain copies of the primary's data and can optionally serve read requests.
- Arbiter Node: Participates in elections but does not store data. It is used to maintain an odd number of voting members in the replica set.

And it is recommended to create a cluster with at least three nodes to ensure high availability, one primary and two secondary nodes.

### Horizontal scaling

#### Scale-out

Horizontal scaling out cluster by adding ONE more replica:

```yaml
# cat examples/mongodb/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-scale-out
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: mongodb
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/mongodb/scale-out.yaml
```

After applying the operation, you will see a new pod created and the cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `secondary`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe ops mongo-scale-out
```

#### Scale-in

Horizontal scaling in cluster by deleting ONE replica:

```yaml
# cat examples/mongodb/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-scale-in
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: mongodb
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/mongodb/scale-in.yaml
```

On horizontal scaling in/out, member list of the replica set will be updated to make sure the cluster is healthy.

You may verify the full list of members in the replica set by connecting to any pod, and  running the following command:

```bash
mongo-cluster-mongodb > rs.status();
```

#### Set Specified Replicas Offline

There are cases where you want to set a specified replica offline, when it is problematic or you want to do some maintenance work on it. You can use the `onlineInstancesToOffline` field in the `spec.horizontalScaling.scaleIn` section to specify the instance names that need to be taken offline.

```yaml
# snippet of opsrequest
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
spec:
  clusterName: mongo-cluster
  horizontalScaling:
  - componentName: mongodb
    # Specifies the replica changes for scaling out components
    scaleIn:
      onlineInstancesToOffline:
        - 'mongo-cluster-mongodb-1'  # Specifies the instance names that need to be taken offline
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mongodb
      replicas: 3 # set desired number of replicas
      # Optional. Specifies the names of instances to be transitioned to offline status.
      # If no specified, KubeBlocks will select the instances in descending ordinal number order.
      offlineInstances:
      - mongo-cluster-mongodb-1
```

### Vertical scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```yaml
# cat examples/mongodb/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-verticalscaling
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: mongodb
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/mongodb/verticalscale.yaml
```

You will observe that the `secondary` pods are recreated first, followed by the `primary` pod, to ensure the availability of the cluster.

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mongodb
      replicas: 3
      resources:
        requests:
          cpu: "1"       # Update the resources to your need.
          memory: "2Gi"  # Update the resources to your need.
        limits:
          cpu: "2"       # Update the resources to your need.
          memory: "4Gi"  # Update the resources to your need.
```

### Expand volume

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
# cat examples/mongodb/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-volumeexpansion
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: mongodb
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/mongodb/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=mongo-cluster -n default
```

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
apiVersion: apps.kubeblocks.io/v1
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mongodb
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

Restart the specified components in the cluster

```yaml
# cat examples/mongodb/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: mongodb

```

```bash
kubectl apply -f examples/mongodb/restart.yaml
```

### Stop

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```yaml
# cat examples/mongodb/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  type: Stop

```

```bash
kubectl apply -f examples/mongodb/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mongodb
      stop: true  # set stop `true` to stop the component
      replicas: 3
```

### Start

Start the stopped cluster

```yaml
# cat examples/mongodb/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  type: Start

```

```bash
kubectl apply -f examples/mongodb/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mongodb
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 3
```

### Switchover

A switchover in database clusters is a planned operation that transfers the primary (leader) role from one database instance to another. The goal of a switchover is to ensure that the database cluster remains available and operational during the transition.

To promote a non-primary or non-leader instance as the new primary or leader of the cluster:

```yaml
# cat examples/mongodb/switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-switchover
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: mongodb
    # Specifies the instance to become the primary or leader during a switchover operation. The value of `instanceName` can be either:
    # - "*" (wildcard value): - Indicates no specific instance is designated as the primary or leader.
    # - A valid instance name (pod name)
    instanceName: '*'

```

```bash
kubectl apply -f examples/mongodb/switchover.yaml
```

### Switchover-specified-instance

Switchover a specified instance as the new primary or leader of the cluster

```yaml
# cat examples/mongodb/switchover-specified-instance.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-switchover-specify
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: mongodb
    # Specifies the instance to become the primary or leader during a switchover operation. The value of `instanceName` can be either:
    # - "*" (wildcard value): - Indicates no specific instance is designated as the primary or leader.
    # - A valid instance name (pod name)
    instanceName: mongo-cluster-mongodb-2

```

```bash
kubectl apply -f examples/mongodb/switchover-specified-instance.yaml
```

### Reconfigure

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```yaml
# cat examples/mongodb/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-reconfiguring
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: mongodb
   # Contains a list of ConfigurationItem objects, specifying the Component's configuration template name, upgrade policy, and parameter key-value pairs to be updated.
    configurations:
      # Sets the parameters to be updated. It should contain at least one item.
      # The keys are merged and retained during patch operations.
    - keys:
        # Represents the unique identifier for the ConfigMap.
      - key: mongodb.conf
        # Defines a list of key-value pairs for a single configuration file.
        # These parameters are used to update the specified configuration settings.
        parameters:
          # Represents the name of the parameter that is to be updated.
        - key: systemLog.verbosity
          # Represents the parameter values that are to be updated.
          # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
          value: "1"
        - key: systemLog.quiet
          value: "true"
      # Specifies the name of the configuration template.
      name: mongodb-config
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring

```

```bash
kubectl apply -f examples/mongodb/configure.yaml
```

This example sets `systemLog.verbosity` to `1` and `systemLog.quiet`to `true`.
You may log into the instance to verify the change:

1. Connect to MongoDB using mongosh.
2. Execute an admin command to retrieve values.

```bash
const config = db.adminCommand({ getCmdLineOpts: 1 });
print("systemLog.quiet:", config.parsed.systemLog.quiet);
print("systemLog.verbosity:", config.parsed.systemLog.verbosity);
```

### Backup

> [!IMPORTANT] Before you start, please create a `BackupRepo` to store the backup data. Refer to [BackupRepo](../docs/create-backuprepo.md) for more details.

You may find the supported backup methods in the `BackupPolicy` of the cluster, and find how these methods will be scheduled in the `BackupSchedule` of the cluster.

The list of supported backup methods can be found by following command:

```bash
# mongo-cluster-mongodb-backup-policy is the backup policy name
kubectl get backuppolicy mongo-cluster-mongodb-backup-policy -oyaml | yq '.spec.backupMethods[].name'
```

TO create a backup for the the cluster using `datafile` method:

```yaml
# cat examples/mongodb/backup.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: mongo-cluster-backup
  namespace: default
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - dump
  # - volume-snapshot
  # - datafile
  backupMethod: datafile
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: mongo-cluster-mongodb-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete

```

```bash
kubectl apply -f examples/mongodb/backup.yaml
```

Information, such as `path`, `timeRange` about the backup will be recorded into the `Backup` resource.

Alternatively, you can update the `BackupSchedule` to enable the method `xtrabackup` to schedule base backup periodically.

### Restore

Restore a new cluster from a backup

1. Get the list of accounts and their passwords from the backup:

```bash
kubectl get backup mongo-cluster-backup -ojsonpath='{.metadata.annotations.kubeblocks\.io/encrypted-system-accounts}'
```

1. Update `examples/mongodb/restore.yaml` and set placeholder `<ENCRYPTED-SYSTEM-ACCOUNTS>` with your own settings and apply it.

```yaml
# cat examples/mongodb/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mongo-cluster-restore
  namespace: default
  annotations:
    # e.g. set  "encryptedSystemAccounts": {\"root\":\"ENCRYPTEDPASSWORD\"}
    kubeblocks.io/restore-from-backup: '{"mongodb":{"encryptedSystemAccounts":"<ENCRYPTED-SYSTEM-ACCOUNTS>","name":"mongo-cluster-backup","namespace":"default","volumeRestorePolicy":"Parallel"}}'
spec:
  terminationPolicy: Delete
  clusterDef: mongodb
  topology: replicaset
  componentSpecs:
    - name: mongodb
      serviceVersion: "6.0.16"
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
kubectl apply -f examples/mongodb/restore.yaml
```

### Expose

Expose a cluster with a new endpoint

#### Enable

```yaml
# cat examples/mongodb/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-expose-enable
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: mongodb
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      roleSelector: primary
      serviceType: LoadBalancer
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Enable
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Expose

```

```bash
kubectl apply -f examples/mongodb/expose-enable.yaml
```

#### Disable

```yaml
# cat examples/mongodb/expose-disable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mongo-expose-disable
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mongo-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: mongodb
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
kubectl apply -f examples/mongodb/expose-disable.yaml
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
    componentSelector: mongodb
    name: mongodb-vpc
    serviceName: mongodb-vpc
    # optional. it specify defined role as selector for the service.
    # onece specified, service will select and route traffic to Pods with the label
    # "kubeblocks.io/role=<specified-role-name>".
    # valid options are: [primary, secondary]
    roleSelector: primary
    spec:  # defines the behavior of a K8s service.
      ipFamilyPolicy: PreferDualStack
      ports:
      - name: tcp-mongodb
        # port to expose
        port: 27017
        protocol: TCP
        targetPort: mongodb
      # Determines how the Service is exposed. Defaults to 'ClusterIP'.
      # Valid options are [`ClusterIP`, `NodePort`, and `LoadBalancer`]
      type: LoadBalancer
  componentSpecs:
    - name: mongodb
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

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster mongo-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster mongo-cluster
```

## References

