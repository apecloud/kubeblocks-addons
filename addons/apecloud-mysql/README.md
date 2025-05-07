# ApeCloud MySQL on KubeBlocks

## Overview

ApeCloud MySQL is a MySQL-compatible database that implements high availability through a RAFT consensus protocol cluster.

### Key Characteristics

- **MySQL 8.0 Compatibility**: Full support for MySQL 8.0 syntax and features
- **High Availability**: Automatic leader election and failover via RAFT
- **Consistency Guarantees**: Strong consistency across replicas

### RAFT Implementation Features

- Leader-based replication with log synchronization
- Automatic failover with minimal downtime
- Split-brain prevention through quorum requirements

## Features in KubeBlocks

### Cluster Management Operations

| Operation |Supported | Description |
|-----------|-------------|----------------------|
| **Restart** | YES | • Ordered sequence (followers first)<br/>• Health checks between restarts |
| **Stop/Start** | YES |  • Graceful shutdown<br/>• Fast startup from persisted state |
| **Horizontal Scaling** |YES |  • Adjust replica count dynamically<br/>• Automatic data replication<br/> |
| **Vertical Scaling** | YES |  • Adjust CPU/Memory resources<br/>• Rolling updates for minimal downtime<br/>• Adaptive Parameters Reconfiguration, such as buffer pool size/max connections |
| **Volume Expansion** | YES |  • Online storage expansion<br/>• No downtime required |
| **Reconfiguration** | YES | • Dynamic/Static parameter updates<br/>• Validation rules<br/>• Versioned history |
| **Service Exposure** | YES |  • Multiple exposure types (ClusterIP/NodePort/LB)<br/>• Role-based routing |
| **Switchover** | YES |  • Planned leader transfer<br/>• Zero data loss guarantee |

### Data Protection

| Type       | Method     | Details |
|---------------|------------|---------|
| Full Backup   | xtrabackup | • using Percona XtraBackup to perform a full backup <br/>• Upload backup file using `datasafed push`
| Continuous Backup | archive-binlog | • Flushes binlogs when needed (size or time thresholds) <br/> • Upload binlogs using `wal-g binlog-push` <br/> • Purges expired binlogs |

### Supported Versions

| MySQL Version | ApeCloud MySQL Version | Notes |
|--------------|-----------------------|-------|
| 8.0.30       | 8.0.30 | GA release |

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes Environment**:
   - Cluster v1.21+
   - `kubectl` installed ([Installation Guide](https://kubernetes.io/docs/tasks/tools/))
   - Helm v3+ ([Installation Guide](https://helm.sh/docs/intro/install/))

2. **KubeBlocks Setup**:
   - KubeBlocks installed and running ([Installation](../docs/prerequisites.md))
   - ApeCloud MySQL Addon enabled ([Addon Setup](../docs/install-addon.md))
   - ETCD Addon enabled ([Addon Setup](../docs/install-addon.md))

3. **Namespace Setup**:
   Create an isolated namespace for this tutorial:

  ```bash
  kubectl create ns demo
  ```

## Lifecycle Management Operations

### Cluster Provisioning

#### Quick Start

To deploy a basic ApeCloud MySQL cluster with RAFT consensus:

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
kubectl get cluster acmysql-cluster -w -n demo
```

<details open>
<summary>Expected Output</summary>

```bash
NAME              CLUSTER-DEFINITION   TERMINATION-POLICY   STATUS    AGE
acmysql-cluster   apecloud-mysql       Delete               Running   11m
```

</details>

and three replicas are `Running` with roles `leader`,  `follower` and `follower` separately. To check the roles of the replicas, you can use following command:

```bash
kubectl get po -l  app.kubernetes.io/instance=acmysql-cluster -L kubeblocks.io/role -n demo
```

<details open>
<summary>Expected Output</summary>

```bash
NAME                      READY   STATUS    RESTARTS   AGE   ROLE
acmysql-cluster-mysql-0   5/5     Running   0          12m   leader
acmysql-cluster-mysql-1   5/5     Running   0          12m   follower
acmysql-cluster-mysql-2   5/5     Running   0          12m   follower
```

</details>

#### Version-Specific Cluster

If you want to create a cluster of specified version, set the `spec.componentSpecs.serviceVersion` field in the yaml file before applying it:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
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

<details open>
<summary>Expected Output</summary>

```bash
NAME             VERSIONS   STATUS      AGE
apecloud-mysql   8.0.30     Available   5d
```

</details>

### Cluster Restart

Restart the cluster components with zero downtime:

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

This operation can only be performed via `OpsRequest`, and there is no corresponding CLUSTER API operation - because restart is not a declaration but an action.

> [!NOTE]
> The restart follows a safe sequence:
>
> 1. All follower replicas are restarted first
> 2. Leader replica is restarted last
> 3. Transfer leadership to a healthy follower before restarting Leader replica
> This ensures continuous availability during the restart process.

### Cluster Stop and Start

#### Stopping the Cluster

Gracefully stop the cluster to conserve resources while retaining all data (PVC). It is ideal for cost savings during inactive periods.

**Stop via OpsRequest**

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
    - name: mysql
      stop: true  # Set to true to stop the component
      replicas: 3
```

#### Starting the Cluster

Start the cluster from its stopped state:

**Start via OpsRequest**

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

**Start via Cluster API**

Update the cluster spec directly:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mysql
      stop: false  # Set to false to start the component or remove the field (default to false)
      replicas: 3
```

## Scaling Operations

### Horizontal Scaling

> [!NOTE]
> As per the ApeCloud MySQL documentation, the number of Raft replicas should be odd to avoid split-brain scenarios.
> Make sure the number of ApeCloud MySQL replicas, is always odd after Horizontal Scaling.

#### Scale Out Operation

Add a new replica to the cluster:

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

To Check detailed operation status

```bash
kubectl describe ops -n demo acmysql-scale-out
```

**Expected Workflow**:

1. New pod is provisioned with `Pending` status
2. Data is cloned from leader to new replica
3. New pod transitions to `Running` with `follower` role
4. Cluster status changes from `Updating` to `Running`

> [!IMPORTANT]
> Scaling considerations:
>
> - Always maintain an **odd number** of replicas for RAFT quorum
> - Scaling operations are sequential - one replica at a time
> - Data cloning may take time depending on dataset size

To verify the new replica's status:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=acmysql-cluster -L kubeblocks.io/role
```

### Scale In Operation

#### Standard Scale In Operation

Remove a replica from the cluster while maintaining RAFT quorum:

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

Check detailed operation status:

```bash
kubectl describe ops -n demo acmysql-scale-in
```

**Expected Workflow**:

1. Selected replica (the one with the largest ordinal) is removed from Raft group
2. Pod is terminated gracefully
3. Cluster status changes from `Updating` to `Running`

**Verification**:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=acmysql-cluster
```

> [!IMPORTANT]
> **Scaling Considerations**:
>
> - Minimum 3 replicas required for HA
> - Always maintain odd number of replicas
> - Scale operations are sequential (one at a time)
> - Monitor cluster health after scaling

#### Targeted Instance Scale In

For cases where you need to take a specific problematic replica offline for maintenance:

```yaml
# cat examples/apecloud-mysql/scale-in-specified-pod.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-scale-in-specified-pod
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
      # Specifies the instance names that need to be taken offline
      onlineInstancesToOffline:
        - 'acmysql-cluster-mysql-1'


```

```bash
kubectl apply -f examples/apecloud-mysql/scale-in-specified-pod.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo acmysql-scale-in-specified-pod
```

**Expected Workflow**:

1. Selected replica (specified in `onlineInstancesToOffline`) is removed from Raft group
2. Pod is terminated gracefully
3. Cluster status changes from `Updating` to `Running`

#### Horizontal Scaling via Cluster API

Directly update replica count via Cluster API:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: apecloud-mysql
      replicas: 3  # Adjust replicas for scaling in and out.
      offlineInstances:
        - acmysql-cluster-mysql-1 # for targetd-instance scale-in scenario, default to empty list.
```

### Vertical Scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:

- CPU cores/processing power
- Memory (RAM)

#### Vertical Scaling via OpsRequest API

Perform vertical scaling using a operation request:

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

**Expected Workflow**:

1. Followers are updated first (one at a time)
1. Leader is updated last after followers are healthy
1. Cluster status transitions from `Updating` to `Running`

#### Vertical Scaling via Cluster API

Directly modify cluster specifications for vertical scaling:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mysql
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

## Reconfiguration Management

### Parameter Types

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability.

| Type | Restart Required | Scope | Example Parameters |
|------|------------------|-------|--------------------|
| **Dynamic** | No | Immediate effect | `max_connections`, `innodb_buffer_pool_size` |
| **Static** | Yes | After restart | `performance_schema`, `log_bin` |

### Reconfiguration

1. **Prepare Configuration**:

```yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
spec:
  clusterRef: acmysql-cluster
  type: Reconfig
  reconfig:
    componentName: mysql
    configurations:
    - name: mysql-config
      parameters:
        max_connections: "600"
        innodb_buffer_pool_size: "512M"
```

2. **Apply Changes**:

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
    parameters:
      # Represents the name of the parameter that is to be updated.
    - key: innodb_buffer_pool_size
      # Represents the parameter values that are to be updated.
      # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
      value: 512M
    - key: max_connections
      value: '600'
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0

```

```bash
kubectl apply -f examples/apecloud-mysql/configure.yaml
```

3. **Monitor Progress**:

```bash
kubectl describe ops acmysql-reconfiguring -n demo
```

4. **Verify Changes**:

```sql
-- On leader replica
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
```

> [!IMPORTANT]
>
> - Static changes trigger rolling restarts
> - Monitor cluster health during reconfiguration

<details open>

<summary>How to find the list of dynamic/static parameters</summary>

Behavior of Parameters, including parameters scope such as dynamic/static/immutable, or parameters validation rules such as value types, ranges of values, are defined in KubeBlocks `ParameterDefinition`.

You may fetch the list of dynamic parameters for ApeCloud MySQL using:

```bash
kubectl get pd apecloud-mysql8.0-pd -oyaml | yq '.spec.staticParameters'
kubectl get pd apecloud-mysql8.0-pd -oyaml | yq '.spec.dynamicParameters'
```

</details>

### Configuration Validation

KubeBlocks will validate the parameter values and types before applying changes.

For example, `max_connections` in mysql should obey this rule:

```
// The number of simultaneous client connections allowed. should be a integer, btw [1, 100000]
max_connections?: int & >=1 & <=100000
```

And if you somehow give a string to this value like:

```yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
spec:
  type: Reconfiguring
  clusterName: acmysql-cluster
  reconfigures:
  - componentName: mysql
    parameters:
    - key: max_connections
      value: 'abc'
```

This OpsRequest fails fast with message `failed to validate updated config: [failed to parse field max_connections: [strconv.Atoi: parsing "STRING": invalid syntax]]`

## High Availability

### Switchover (Planned Leader Transfer)

SwitchOver is a controlled operation that safely transfers leadership while maintaining:

- Continuous availability
- Zero data loss
- Minimal performance impact

<details>
<summary>Developer: Switchover Actions</summary>
KubeBlocks executes SwitchOver actions defined in `componentdefinition.spec.lifecycleActions.switchover`.

To get the SwitchOver actions for ApeCloud MySQL:

```bash
kubectl get cmpd apecloud-mysql-1.0.0-alpha.0 -oyaml | yq '.spec.lifecycleActions.switchover'
```

</details>

#### Prerequisites

- Cluster must be in `Running` state
- No ongoing maintenance operations

#### Switchover Types

1. **Automatic Switchover** (No preferred candidate):

```yaml
# cat examples/apecloud-mysql/switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-switchover
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: mysql
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: acmysql-cluster-mysql-0

```

   ```bash
   kubectl apply -f examples/apecloud-mysql/switchover.yaml
   ```

2. **Targeted Switchover** (Specific instance):

```yaml
# cat examples/apecloud-mysql/switchover-specified-instance.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: acmysql-switchover-specify
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: acmysql-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: mysql
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: acmysql-cluster-mysql-0
    # If CandidateName is specified, the role will be transferred to this instance.
    # The name must match one of the pods in the component.
    # Refer to ComponentDefinition's Swtichover lifecycle action for more details.
    candidateName: acmysql-cluster-mysql-1

```

   ```bash
   kubectl apply -f examples/apecloud-mysql/switchover-specified-instance.yaml
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
  kubectl logs -n demo <pod-name> -c kbagent # check on leader replica
  kubectl get events -n demo --field-selector involvedObject.name=<cluster-name>
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

#### Volume Expansion via Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mysql
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

- Disable Service

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
      componentSelector: mysql
      name: acmysql-vpc
      serviceName: acmysql-vpc
      roleSelector: leader  # [leader, follower] for ApeCloud-MySQL
      spec:
        ipFamilyPolicy: PreferDualStack
        ports:
        - name: tcp-mysql
          port: 3306
          protocol: TCP
          targetPort: mysql
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
   kubectl get backuppolicy -n demo -l app.kubernetes.io/instance=acmysql-cluster
   ```

2. **View default BackupSchedule**:

   ```bash
   kubectl get backupschedule -n demo -l app.kubernetes.io/instance=acmysql-cluster
   ```

#### Backup Execution

1. **On-Demand Backup**:

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

2. **Monitor Progress**:

   ```bash
   kubectl get backup -n demo -w
   kubectl describe backup <backup-name> -n demo
   ```

3. **Verify Completion**:
   - Check status is `Completed`
   - Verify backup size matches expectations
   - Validate backup metadata

#### Scheduled Backups

Update `BackupSchedule` to schedule enable(`enabled`) backup methods and set the time (`cronExpression`) to your need:

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
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
    enabled: true # set to `true` to schedule base backup periodically
    retentionPeriod: 7d # set the retention period to your need
```

#### Troubleshooting

- **Backup Stuck**:

  ```bash
  kubectl describe backup <name> -n demo  # describe backup
  kubectl get po -n demo -l app.kubernetes.io/instance=acmysql-cluster,dataprotection.kubeblocks.io/backup-policy=acmysql-cluster-mysql-backup-policy # get list of pods working for Backups
  kubectl logs -n demo <backup-pod> # check backup pod logs
  ```

### Restore Operations

#### Prerequisites

1. **Backup Verification**:
   - Backup must be in `Completed` state

2. **Cluster Resources**:
   - Sufficient CPU/memory for new cluster
   - Available storage capacity
   - Network connectivity between backup repo and new cluster

3. **Credentials**:
   - System account encryption keys

#### Restore Workflow

1. **Identify Backup**:

   ```bash
   kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Full,app.kubernetes.io/instance=acmysql-cluster # get the list of full backups
   ```

2. **Prepare Credentials**:

   ```bash
   # Get encrypted system accounts
    kubectl get backup acmysql-cluster-backup -n demo -ojson | jq -r '.metadata.annotations | ."kubeblocks.io/encrypted-system-accounts" | fromjson .mysql | tojson |gsub("\""; "\\"")'
   ```

3. **Configure Restore**:
   Update `examples/apecloud-mysql/restore.yaml` with:
   - Backup name and namespace: from step 1
   - Encrypted system accounts: from step 2
   - Target cluster configuration

4. **Execute Restore**:

```yaml
# cat examples/apecloud-mysql/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: acmysql-cluster-restore
  namespace: demo
  annotations:
    kubeblocks.io/restore-from-backup: '{"mysql":{"encryptedSystemAccounts":"<ENCRYPTED-SYSTEM-ACCOUNTS>","name":"acmysql-cluster-backup","namespace":"demo","volumeRestorePolicy":"Parallel"}}'
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

5. **Monitor Progress**:

   ```bash
   # Watch restore status
   kubectl get restore -n demo -w

   # View detailed logs
   kubectl get cluster -n demo -w
   ```

## Monitoring & Observability

### Prerequisites

1. **Prometheus Operator**: Required for metrics collection
   - Skip if already installed
   - Install via: [Prometheus Operator Guide](../docs/install-prometheus.md)

2. **Access Credentials**: Ensure you have:
   - `kubectl` access to the cluster
   - Grafana admin privileges (for dashboard import)

3. **Cluster created with Exporter enabled**
    - create a ApeCloud-MySQL Cluster with exporter running as sidecar (`disableExporter: false`)
    - Skip if already created

### Metrics Collection Setup

#### 1. Configure PodMonitor

1. **Get Exporter Details**:

   ```bash
   kubectl get po -n demo acmysql-cluster-mysql-0 -oyaml | yq '.spec.containers[] | select(.name=="mysql-exporter") | .ports'
   ```

  <details open>
  <summary>Expected Output:</summary>

   ```text
   - containerPort: 9104
     name: http-metrics
     protocol: TCP
   ```

  </details>

2. **Verify Metrics Endpoint**:

   ```bash
   kubectl -n demo exec -it pods/acmysql-cluster-mysql-0 -- \
     curl -s http://127.0.0.1:9104/metrics | head -n 50
   ```

3. **Apply PodMonitor**:

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

#### 2. Grafana Dashboard Setup

1. **Import Dashboard**:
   - URL: [ApeCloud MySQL Dashboard](https://raw.githubusercontent.com/apecloud/kubeblocks-addons/refs/heads/main/addons/apecloud-mysql/dashboards/mysql.json)

2. **Verification**:
   - Confirm metrics appear in Grafana within 2-5 minutes
   - Check for "UP" status in Prometheus targets

### Troubleshooting

- **No Metrics**: check Prometheus

  ```bash
  kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
  kubectl logs -n monitoring <prometheus-pod-name> -c prometheus
  ```

- **Dashboard Issues**: check indicator labels and dashboards
  - Verify Grafana DataSource points to correct Prometheus instance
  - Check for template variable mismatches

## Cleanup

To permanently delete the cluster and all associated resources:

1. First modify the termination policy to ensure all resources are cleaned up:

```bash
# Set termination policy to WipeOut (deletes all resources including PVCs)
kubectl patch cluster -n demo acmysql-cluster \
  -p '{"spec":{"terminationPolicy":"WipeOut"}}' \
  --type="merge"
```

2. Verify the termination policy was updated:

```bash
kubectl get cluster -n demo acmysql-cluster -o jsonpath='{.spec.terminationPolicy}'
```

3. Delete the cluster:

```bash
kubectl delete cluster -n demo acmysql-cluster
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

<!--
## SmartEngine

SmartEngine is an OLTP storage engine based on LSM-Tree architecture and supports complete ACID transaction constraints.

### Enable

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
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring

```

```bash
kubectl apply -f examples/apecloud-mysql/smartengine-enable.yaml
```

### Disable

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

### Create Cluster with Proxy

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
kubectl port-forward svc/acmysql-proxy-cluster-wescale 15306:15306 -n demo
```

- login to with the following command:

```bash
mysql -h127.0.0.1 -P 15306 -u<userName> -p <userPasswd>
```

and credentials can be found in the `secret` resource:

```bash
userName=$(kubectl get secret -n demo acmysql-proxy-cluster-mysql-account-root -ojsonpath='{.data.username}' | base64 -d)
userPasswd=$(kubectl get secret -n demo acmysql-proxy-cluster-mysql-account-root -ojsonpath='{.data.password}' | base64 -d)
```

You may scale wescale and ETCD components as needed.

## Appendix

### Connecting to ApeCloud MySQL

To connect to the ApeCloud MySQL cluster, you can:

- port forward the MySQL service to your local machine:

```bash
kubectl port-forward svc/acmysql-cluster-mysql 3306:3306 -n demo
```

- or expose the MySQL service to the internet, as mentioned in the [Networking](#networking) section.

Then you can connect to the MySQL cluster with the following command:

```bash
mysql -h <endpoint> -P 3306 -u <userName> -p <userPasswd>
```

and credentials can be found in the `secret` resource:

```bash
userName=$(kubectl get secret -n demo acmysql-cluster-mysql-account-root -ojsonpath='{.data.username}' | base64 -d)
userPasswd=$(kubectl get secret -n demo acmysql-cluster-mysql-account-root -ojsonpath='{.data.password}' | base64 -d)
```

### How to Check the Status of ApeCloud MySQL

You can check the status of the ApeCloud MySQL cluster with the following command on `leader` replica:

```bash
mysql > select * from information_schema.WESQL_CLUSTER_GLOBAL;
+-----------+--------------------------------------------------------------+-------------+------------+----------+-----------+------------+-----------------+----------------+---------------+------------+--------------+
| SERVER_ID | IP_PORT                                                      | MATCH_INDEX | NEXT_INDEX | ROLE     | HAS_VOTED | FORCE_SYNC | ELECTION_WEIGHT | LEARNER_SOURCE | APPLIED_INDEX | PIPELINING | SEND_APPLIED |
+-----------+--------------------------------------------------------------+-------------+------------+----------+-----------+------------+-----------------+----------------+---------------+------------+--------------+
|         1 | acmysql-cluster-mysql-0.acmysql-cluster-mysql-headless:13306 |        1757 |          0 | Leader   | Yes       | No         |               5 |              0 |          1757 | No         | No           |
|         2 | acmysql-cluster-mysql-1.acmysql-cluster-mysql-headless:13306 |        1757 |       1758 | Follower | Yes       | No         |               5 |              0 |          1756 | Yes        | No           |
|         3 | acmysql-cluster-mysql-2.acmysql-cluster-mysql-headless:13306 |        1757 |       1758 | Follower | No        | No         |               5 |              0 |          1756 | Yes        | No           |
+-----------+--------------------------------------------------------------+
3 rows in set (0.00 sec)
mysql > select * from information_schema.WESQL_CLUSTER_HEALTH;
+-----------+--------------------------------------------------------------+----------+-----------+---------------+-----------------+
| SERVER_ID | IP_PORT                                                      | ROLE     | CONNECTED | LOG_DELAY_NUM | APPLY_DELAY_NUM |
+-----------+--------------------------------------------------------------+----------+-----------+---------------+-----------------+
|         1 | acmysql-cluster-mysql-0.acmysql-cluster-mysql-headless:13306 | Leader   | YES       |             0 |               0 |
|         2 | acmysql-cluster-mysql-1.acmysql-cluster-mysql-headless:13306 | Follower | YES       |             0 |               0 |
|         3 | acmysql-cluster-mysql-2.acmysql-cluster-mysql-headless:13306 | Follower | YES       |             0 |               1 |
+-----------+--------------------------------------------------------------+----------+-----------+---------------+-----------------+
3 rows in set (0.00 sec)
```

### List of K8s Resources created when creating an ApeCloud MySQL Cluster

To get the full list of associated resources created by KubeBlocks for given cluster:

```bash
kubectl get cmp,its,po -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # cluster resource
kubectl get backuppolicy,backupschedule,backup -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # data protection resources
kubectl get componentparameter,parameter -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # configuration resources
kubectl get opsrequest -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # opsrequest
kubectl get svc,secret,cm,pvc -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # k8s native resources
```

## References
