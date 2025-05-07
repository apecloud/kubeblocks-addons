# PostgreSQL Addon for KubeBlocks

## Overview

PostgreSQL (Postgres) is an open source object-relational database known for reliability and data integrity.

## Features in KubeBlocks

### Cluster Operations

| Operation          | Supported | Description |
|--------------------|-----------|-------------|
| **Restart** | YES | • Ordered sequence (secondary replicas first)<br/>• Health checks between restarts |
| **Stop/Start** | YES |  • Graceful shutdown<br/>• Fast startup from persisted state |
| **Horizontal Scaling** |YES |  • Adjust replica count dynamically<br/>• Automatic data replication<br/> |
| **Vertical Scaling** | YES |  • Adjust CPU/Memory resources<br/>• Rolling updates for minimal downtime<br/>• Adaptive Parameters Reconfiguration, such as buffer pool size/max connections |
| **Volume Expansion** | YES |  • Online storage expansion<br/>• No downtime required |
| **Reconfiguration** | YES | • Dynamic/Static parameter updates<br/>• Validation rules<br/>• Versioned history |
| **Service Exposure** | YES |  • Multiple exposure types (ClusterIP/NodePort/LB)<br/>• Role-based routing |
| **Switchover** | YES |  • Planned leader transfer<br/>• Zero data loss guarantee |

### Data Protection

| Feature           | Method          | Description |
|-------------------|-----------------|-------------|
| Full Backup       | pg-basebackup   | Uses `pg_basebackup`, a PostgreSQL utility to create a base backup |
| Full Backup       | wal-g  | Uses `wal-g` to create a full backup (requires WAL-G configuration) |
| Continuous Backup | postgresql-pitr | Uploads PostgreSQL Write-Ahead Logging (WAL) files periodically to the backup repository, usually paired with `pg-basebackup`|
| Continuous Backup | wal-g-archive | Uploads PostgreSQL Write-Ahead Logging (WAL) files periodically to the backup repository, usually paired with `wal-g`|

### Supported Versions

| Version | Available Releases |
|---------|--------------------|
| 12.x    | 12.14.0, 12.14.1, 12.15.0 |
| 14.x    | 14.7.2, 14.8.0 |
| 15.x    | 15.7.0 |
| 16.x    | 16.4.0 |

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes Environment**:
   - Cluster v1.21+
   - `kubectl` installed ([Installation Guide](https://kubernetes.io/docs/tasks/tools/))
   - Helm v3+ ([Installation Guide](https://helm.sh/docs/intro/install/))

2. **KubeBlocks Setup**:
   - KubeBlocks installed and running ([Installation](../docs/prerequisites.md))
   - PostgreSQL Addon enabled ([Addon Setup](../docs/install-addon.md))

3. **Namespace Setup**:
   Create an isolated namespace for this tutorial:

   ```bash
   kubectl create ns demo
   ```

## Lifecycle Management Operations

### Cluster Provisioning

#### Quick Start

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
      # Valid options are: [12.14.0,12.14.1,12.15.0,14.7.2,14.8.0,15.7.0,16.4.0]
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

#### Version-Specific Cluster

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
      # Valid options are: [12.14.0,12.14.1,12.15.0,14.7.2,14.8.0,15.7.0,16.4.0]
      serviceVersion: "14.7.2"
```

The list of supported versions can be found by following command:

```bash
kubectl get cmpv postgresql
```

<details open>
<summary>Expected Output:</summary>

```bash
NAME         VERSIONS                                              STATUS      AGE
postgresql   12.14.0,12.14.1,12.15.0,14.7.2,14.8.0,15.7.0,16.4.0   Available   Xd
```

</details>

### Cluster Restart

#### Restart

Restart specified components in the cluster, and instances will be recreated one after another to ensure the availability of the cluster.

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

This operation can only be performed via `OpsRequest`, and there is no corresponding CLUSTER API operation - because restart is not a declaration but an action.

> [!NOTE]
> The restart follows a safe sequence:
>
> 1. All secondary replicas are restarted first
> 2. Primary replica will be restarted last
> 3. Transfer leadership to a healthy secondary before restarting Primary replica
> This ensures continuous availability during the restart process.

### Cluster Stop and Start

#### Stopping the cluster

Gracefully stop the cluster to conserve resources while retaining all data (PVC). It is ideal for cost savings during inactive periods.

**Stop via OpsRequest**

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

> [!NOTE]
> When stopped:
>
> - All compute resources are released
> - Persistent volumes remain intact
> - No data is lost

**Stop via Cluster API**

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

#### Starting the Cluster

**Start via OpsRequest**

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

**Start via Cluster API**

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

### Minor Version Upgrade

> [!IMPORTANT]
> Do remember to to check the compatibility of versions before upgrading the cluster.

**Upgrade via OpsRequest**

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

**Upgrade via Cluster API**

Alternatively, you may modify the `spec.componentSpecs.serviceVersion` field to the desired version to upgrade the cluster.

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

## Scaling Operations

### Horizontal Scaling

#### Scale Out Operation

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

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe -n demo ops pg-scale-out
```

**Expected Workflow**:

1. New pod is provisioned with `Pending` status
2. Data is cloned from primary to new replica
3. New pod transitions to `Running` with `secondary` role
4. Cluster status changes from `Updating` to `Running`

> [!IMPORTANT]
> Scaling considerations:
>
> - Scaling operations are sequential - one replica at a time
> - Data cloning may take time depending on dataset size

To verify the new replica's status:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=pg-cluster -L kubeblocks.io/role
```

#### Scale In Operation

#### Standard Scale In Operation

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

Check detailed operation status:

```bash
kubectl describe ops -n demo pg-scale-in
```

**Expected Workflow**:

1. Selected replica (the one with the largest ordinal) is removed
2. Pod is terminated gracefully
3. Cluster status changes from `Updating` to `Running`

#### Targeted Instance Scale In

For cases where you need to take a specific problematic replica offline for maintenance:

```yaml
# cat examples/postgresql/scale-in-specified-pod.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-scale-in-specified-pod
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
    scaleIn:
      # Specifies the instance names that need to be taken offline
      onlineInstancesToOffline:
        - 'pg-cluster-postgresql-1'


```

```bash
kubectl apply -f examples/postgresql/scale-in-specified-pod.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo pg-scale-in-specified-pod
```

**Expected Workflow**:

1. Selected replica (specified in `onlineInstancesToOffline`) is removed
2. Pod is terminated gracefully
3. Cluster status changes from `Updating` to `Running`

#### Horizontal Scaling via Cluster API

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
      offlineInstances:
        - pg-cluster-postgresql-1 # for targeted-instance scale-in scenario, default to empty list.
```

### Vertical Scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:

- CPU cores/processing power
- Memory (RAM)

#### Vertical scaling via OpsRequest API

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

**Expected Workflow**:

1. Secondary replicas are updated first (one at a time)
1. Primary is updated last after secondary replicas are healthy
1. Cluster status transitions from `Updating` to `Running`

#### Vertical Scaling via Cluster API

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
| **Dynamic** | No | Immediate effect | `max_connections` |
| **Static** | Yes | After restart | `shared_buffers` |

### Reconfiguration

Reconfigure parameters with the specified components in the cluster

1. **Prepare Configuration**:

```yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-reconfiguring
  namespace: demo
spec:
  type: Reconfiguring
  clusterName: pg-cluster
  reconfigures:
  - componentName: postgresql
    parameters:
    - key: pgaudit.log
      value: 'ddl'
```

2. **Apply Changes**:

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
    - key: pgaudit.log
      # Represents the parameter values that are to be updated.
      # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
      value: read

```

```bash
kubectl apply -f examples/postgresql/configure.yaml
```

This example will change the `pgaudit.log` to `ddl` (default to `ddl,read,write`)

The `pgaudit.log` parameter determines the level of detail and type of events that will be captured in the audit logs. You can configure it to log specific types of operations, such as DDL (data definition language), DML (data manipulation language), role changes, and function calls.
Possible values are:

| Value    | Description |
|----------|-------------|
| none     | No additional logging is performed by pgAudit. |
| ddl      | Logs all Data Definition Language (DDL) statements, such as CREATE, ALTER, DROP, etc. Example: Logging the creation or modification of tables, indexes, views, etc. |
| dml      | Logs all Data Manipulation Language (DML) statements, such as INSERT, UPDATE, DELETE, TRUNCATE, and COPY. Example: Logging changes made to data within tables. |
| role     | Logs all role-related commands, such as GRANT, REVOKE, CREATE ROLE, ALTER ROLE, and DROP ROLE. Example: Logging changes to user permissions or roles. |
| read     | Logs all read operations, such as SELECT and COPY TO. Example: Logging queries that retrieve data from the database. |
| write    | Logs all write operations, such as INSERT, UPDATE, DELETE, TRUNCATE, and COPY FROM. Example: Logging queries that modify data in the database. |
| function | Logs all function calls, including anonymous code blocks (DO blocks). Example: Logging executions of custom functions or procedures. |
| misc     | Logs miscellaneous commands like DISCARD, FETCH, CHECKPOINT, VACUUM, SET, etc. Example: Logging maintenance or administrative commands. |
| all      | Logs everything (including DDL, DML, role changes, function calls, and miscellaneous commands). This setting generates the most detailed logs but may significantly increase log file size and disk usage. |

3. **Monitor Progress**:

```bash
kubectl describe ops pg-reconfiguring -n demo # check ops progress
kubectl describe parameter pg-reconfiguring -n demo  # check parameter updates progress
```

4. **Verify Changes**:

```sql
-- connect to postgresql and check
show pgaudit.log;
```

<details open>

<summary>How to find the list of dynamic/static parameters</summary>

Behavior of Parameters, including parameters scope such as dynamic/static/immutable, or parameters validation rules such as value types, ranges of values, are defined in KubeBlocks `ParameterDefinition`.

You may fetch the list of dynamic parameters for PostgreSQL using:

```bash
kubectl get pd postgresql14-pd-1.0.0-alpha.0 -oyaml | yq '.spec.staticParameters'
kubectl get pd postgresql14-pd-1.0.0-alpha.0 -oyaml | yq '.spec.dynamicParameters'
```

- If `staticParameters` is defined but `dynamicParameters` is not, this implies that `dynamicParameters = All Parameters - staticParameters - immutableParameters.`
- If neither `staticParameters` nor `dynamicParameters` is defined, this means that`dynamicParameters = {}` (an empty set) and `staticParameters = All Parameters - immutableParameters`

### Configuration Validation

KubeBlocks will validate the parameter values and types before applying changes.

For example, `max_connections` in PostgreSQL should obey this rule:

```cue
// Sets the maximum number of concurrent connections.
max_connections?: int & >=6 & <=8388607
```

And if you somehow give a string to this value like:

```yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
spec:
  type: Reconfiguring
  clusterName: pg-cluster
  reconfigures:
  - componentName: postgresql
    parameters:
    - key: max_connections
      value: 'abc'
```

This OpsRequest fails fast with message `failed to validate updated config: [failed to parse field max_connections: [strconv.Atoi: parsing "STRING": invalid syntax]]`

## High Availability

### Switchover

A switchover in database clusters is a planned operation that transfers the primary (leader) role from one database instance to another. The goal of a switchover is to ensure that the database cluster remains available and operational during the transition.

<details>
<summary>Developer: Switchover Actions</summary>

KubeBlocks will perform a switchover operation defined in PostgreSQL's component definition, and you can checkout the details in `componentdefinition.spec.lifecycleActions.switchover`.

You may get the switchover operation details with following command:

```bash
kubectl get cluster -n demo pg-cluster -ojson | jq '.spec.componentSpecs[0].componentDef' | xargs kubectl get cmpd -ojson | jq '.spec.lifecycleActions.switchover'
```

</details>

#### Prerequisites

- Cluster must be in `Running` state
- No ongoing maintenance operations

#### Switchover Types

1. **Automatic Switchover** (No preferred candidate):

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

2. **Targeted Switchover** (Specific instance):

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
  kubectl logs -n demo <pod-name> -c kbagent  # check on primary replica
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

#### Volume Expansion via Cluster API

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

- Disable Service

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

#### Expose SVC via Cluster API

Alternatively, you may expose service by adding a new service to cluster's `spec.services`

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
    # once specified, service will select and route traffic to Pods with the label
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

#### Cloud Provider Load Balancer Annotations

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
   kubectl get backuppolicy -n demo -l app.kubernetes.io/instance=pg-cluster
   ```

2. **View default BackupSchedule**:

   ```bash
   kubectl get backupschedule -n demo -l app.kubernetes.io/instance=pg-cluster
   ```

KubeBlocks supports multiple backup methods for PostgreSQL cluster,  as described in `BackupPolicy` name `pg-cluster-postgresql-backup-policy`, such as `pg-basebackup`, `volume-snapshot`, `wal-g`, etc. We will elaborate on the `pg-basebackup` and `wal-g` backup methods in the following sections to demonstrate how to create full backup and continuous backup for the cluster.

#### Backup Method Option 1: pg_basebackup

|name | backup type |  description |
|--------|-----------|-------------|
| pg-basebackup | full backup |use tool `pg_basebackup`|
| archive-wal | Continuous backup |

**On-Demand Full Backup**

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

1. **Monitor Progress**:

   ```bash
   kubectl get backup -n demo -w
   kubectl describe backup <backup-name> -n demo
   ```

1. **Verify Completion**:
   - Check status is `Completed`
   - Verify backup size matches expectations
   - Validate backup metadata

Information, such as `path`, `timeRange` about the backup will be recorded into the `Backup` resource.

**Scheduled Backups**

Alternatively, you can update the `BackupSchedule` to enable the method `pg-basebackup` to schedule base backup periodically, will be elaborated in the following section.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
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
    enabled: true # set to `true` to schedule base backup periodically
    retentionPeriod: 7d # set the retention period to your need
```

#### Backup Method Option 2: wal-g

WAL-G is an archival restoration tool for PostgreSQL, MySQL/MariaDB, and MS SQL Server (beta for MongoDB and Redis).[^2]

|name | backup type |  description |
|--------|-----------|-------------|
| config-wal-g | N/A| prerequisites of `wal-g` setting up configs and envs and copy `wal-g` binary|
| wal-g-archive | Continuous  | Checks PostgreSQL status, Uploads any pending WAL files, Updates backup status|
| wal-g | full backup | use `wal-g` to perform a full database backup |

**On-Demand Full Backup**

The PostgreSQL WAL-G backup performs a full database backup with following steps:

- Verifies `archive_command` is enabled with WAL-G configuration, set to `envdir /home/postgres/pgdata/wal-g/env /home/postgres/pgdata/wal-g/wal-g wal-push %p`
- Executes a full backup using wal-g backup-push
- Forces a WAL log switch to capture all changes
- Validates and records backup metadata including:
  - Backup name
  - Start/stop timestamps
  - Compressed size
- Writes status information to a JSON file ( and this information will be patched to `Backup` status)

To create a full backup for the cluster using method `wal-g`, please follow steps:

1. configure WAL-G on all PostgreSQL replicas by creating a configuration task:

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
# cat examples/postgresql/reconfig-arhive-command.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pg-cluster-reconfigure-archive-command
  namespace: demo
spec:
  # Specifies the type of this operation.
  type: Reconfiguring
  clusterName: pg-cluster
  reconfigures:
  - componentName: postgresql
    parameters:
      # Represents the name of the parameter that is to be updated.
      # The archive_command parameter in PostgreSQL is used to specify a shell command that the server runs to archive a completed WAL (Write-Ahead Logging) file.
      # Here it sets up the necessary environment variables using envdir and then uses wal-g to archive the WAL file
    - key: archive_command
      value: "'envdir /home/postgres/pgdata/wal-g/env /home/postgres/pgdata/wal-g/wal-g wal-push %p'"
```

```bash
kubectl apply -f examples/postgresql/reconfig-arhive-command.yaml
```

1. insert some data before backup

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
> if there is horizontal scaling out after step 2, you need to do `config-wal-g` again to make sure all replicas are properly configured.

**Scheduled Backups**

Alternatively, you can update the `BackupSchedule` to enable the method `wal-g` to schedule base backup periodically, will be elaborated in the following section.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
spec:
  backupPolicyName: pg-cluster-postgresql-backup-policy
  schedules:
  - backupMethod: wal-g
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

**Continuous Backup**

The method `wal-g-archive` performs continuous backup of WAL files, usually paired with backup method `wal-g`. Its key steps are:

- Processes WAL files marked as ready in `archive_status` directory
- Uses 'wal-g wal-push' command to upload WAL files
- Runs in a continuous loop to ensure all WAL files are archived
- Periodically updates backup metadata including timestamps and sizes (default to every 5 seconds)

To enable continuous backup, you don't need to create a backup, just update `BackupSchedule` and enable the method `wal-g-archive`.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
metadata:
spec:
  backupPolicyName: pg-cluster-postgresql-backup-policy
  schedules:
  - backupMethod: wal-g
    cronExpression: 0 18 * * *
    enabled: true #
    retentionPeriod: 7d
  - backupMethod: wal-g-archive
    cronExpression: '*/5 * * * *'
    enabled: true  # set to `true` to enable continuous backup
    retentionPeriod: 8d # set the retention period to your need
```

1. **Monitor Progress**:

   ```bash
   kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Continuous -w
   # Once the continuous backup is enabled, there will be a `StatefulSet` created to run this task.
   kubectl get sts -n demo -l dataprotection.kubeblocks.io/backup-type=Continuous
   ```

It will run continuously until you disable the method `archive-wal` in the `BackupSchedule`. And the valid time range of the backup will be recorded in the `Backup` status.

```bash
kubectl get backup -n demo -l app.kubernetes.io/instance=pg-cluster -l dataprotection.kubeblocks.io/backup-type=Continuous  -oyaml | yq '.items[].status.timeRange'
```

> [!NOTE]
> Only Continuous Backup has the timeRange.
> And you may restore a cluster to any point valid in this timeRange.

### Restore Operations

#### Prerequisites

1. **Backup Verification**:
   - Full Backup must be in `Completed` state
   - [Optional] for PITR, Continuous Backup must be `Running` with a valid `timeRange` in status.

2. **Cluster Resources**:
   - Sufficient CPU/memory for new cluster
   - Available storage capacity
   - Network connectivity between backup repo and new cluster

3. **Credentials**:
   - System account encryption keys

#### Restore from a Full Backup

1. **Identify Full Backup**:

   ```bash
   kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Full,app.kubernetes.io/instance=pg-cluster # get the list of full backups
   ```

   Pick one of the Backups whose status is `Completed`.

2. **Prepare Credentials**:

  ```bash
  # Get encrypted system accounts
  kubectl get backup <backup-name> -n demo -ojson | jq -r '.metadata.annotations | ."kubeblocks.io/encrypted-system-accounts" | fromjson .postgresql | tojson |gsub("\""; "\\"")'
  ```

3. **Configure Restore**:
   Update `examples/pg-cluster/restore.yaml` with:
   - Backup name and namespace: from step 1
   - Encrypted system accounts: from step 2
   - Target cluster configuration

4. **Execute Restore**:

```yaml
# cat examples/postgresql/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pg-restore
  namespace: demo
  annotations:
    # NOTE: replace <ENCRYPTED-SYSTEM-ACCOUNTS> with the accounts info from you backup
    kubeblocks.io/restore-from-backup: '{"postgresql":{"encryptedSystemAccounts":"<ENCRYPTED-SYSTEM-ACCOUNTS>","name":"<FULL_BACKUP_NAME","namespace":"demo","volumeRestorePolicy":"Parallel"}}'
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

5. **Monitor Progress**:

   ```bash
   # Watch restore status
   kubectl get restore -n demo -w

   # View detailed logs
   kubectl get cluster -n demo -w
   ```

#### Point-in-time Restore

1. **Identify Continuous Backup** and get **timeRange**

  ```bash
  kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Continuous,app.kubernetes.io/instance=pg-cluster  # get the list of Continuous backups
  ```

  ```bash
  kubectl -n demo get backup <backup-name> -oyaml | yq '.status.timeRange' # get valid time range.
  ```

  expected output likes:

  ```text
  end: "2025-05-01T14:28:43Z"
  start: "2025-04-30T07:44:49Z"
  ```

  Pick one of the Backups whose status is `Running`, and `timeRange` is not nil.
  If `timeRamge` is nil, please wait for a few more minutes.

2. **Prepare Credentials**:

  ```bash
  # Get encrypted system accounts
  kubectl get backup <backup-name> -n demo -ojson | jq -r '.metadata.annotations | ."kubeblocks.io/encrypted-system-accounts" | fromjson .postgresql | tojson |gsub("\""; "\\"")'
  ```

3. **Configure Restore**:
   Update `examples/pg-cluster/restore-pitr.yaml` with:
   - Backup name and namespace: from step 1
   - Point time: falls in `timeRange` from Step 1
   - Encrypted system accounts: from step 2
   - Target cluster configuration

4. **Execute Restore**:

```yaml
# cat examples/postgresql/restore-pitr.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pg-restore-pitr
  namespace: demo
  annotations:
    # NOTE: replace <ENCRYPTED-SYSTEM-ACCOUNTS> with the accounts info from you backup
    # NOTE: replace <CONTINUOUS_BACKUP_NAME> with the continuouse backup name
    # NOTE: replace <RESTORE_POINT_TIME>  with a valid time within the backup timeRange.
    kubeblocks.io/restore-from-backup: '{"postgresql":{"encryptedSystemAccounts":"<ENCRYPTED-SYSTEM-ACCOUNTS>","name":"<CONTINUOUS_BACKUP_NAME>","namespace":"demo","restoreTime":"<RESTORE_POINT_TIME>","volumeRestorePolicy":"Parallel"}}'
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
        apps.kubeblocks.postgres.patroni/scope: pg-restore-pitr-postgresql
      replicas: 1
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
   kubectl apply -f examples/postgresql/restore-pitr.yaml
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

## Monitoring & Observability

### Prerequisites

1. **Prometheus Operator**: Required for metrics collection
   - Skip if already installed
   - Install via: [Prometheus Operator Guide](../docs/install-prometheus.md)

2. **Access Credentials**: Ensure you have:
   - `kubectl` access to the cluster
   - Grafana admin privileges (for dashboard import)

3. **Cluster created with Exporter enabled**
    - create a PostgreSQL Cluster with exporter running as sidecar (`disableExporter: false`)
    - Skip if already created

### Metrics Collection Setup

#### 1. Configure PodMonitor

1. **Get Exporter Details**:

```bash
kubectl get po -n demo pg-cluster-postgresql-0 -oyaml | yq '.spec.containers[] | select(.name=="exporter") | .ports '
```

  <details open>
  <summary>Expected Output:</summary>

  ```text
  - containerPort: 9187
    name: http-metrics
    protocol: TCP
  ```

  </details>

  If there is no such container running, please check if this cluster is created with exporter enabled:

  ```bash
  kubectl -n demo get cluster pg-cluster -oyaml | yq '.spec.componentSpecs.disableExporter'
  ```

  </details>

2. **Verify Metrics Endpoint**:

   ```bash
   kubectl -n demo exec -it pods/pg-cluster-postgresql-0 -- \
     curl -s http://127.0.0.1:9187/metrics | head -n 50
   ```

3. **Apply PodMonitor**:

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

#### 2. Grafana Dashboard Setup

1. **Import Dashboard**:
   - URL: [PostgreSQL Dashboard](https://raw.githubusercontent.com/apecloud/kubeblocks-addons/refs/heads/main/addons/postgresql/dashboards/postgresql.json)

2. **Verification**:
   - Confirm metrics appear in Grafana within 2-5 minutes
   - Check for "UP" status in Prometheus targets

> [!NOTE]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Troubleshooting

- **No Metrics**: check prometheus

  ```bash
  kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
  kubectl logs -n monitoring <prometheus-pod-name> -c prometheus
  ```

- **Dashboard Issues**: check indicator labels and dashboards
  - Verify Grafana DataSource points to correct Prometheus instance
  - Check for template variable mismatches

## Cleanup

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo pg-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo pg-cluster
```

## Appendix

### How to Check Compatible versions

Versions and it compatibility rules are embedded in `ComponentVersion` CR in KubeBlocks.
To the the list of compatible versions:

```bash
kubectl get cmpv postgresql -ojson | jq '.spec.compatibilityRules'
```

<details open>

<summary>Expected output</summary>

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

</details>

Releases are grouped by component definitions, and each group has a list of compatible releases.
In this example, it shows you can upgrade from version `12.14.0` to `12.14.1` or `12.15.0`, and upgrade from `14.7.2` to `14.8.0`.
But cannot upgrade from `12.14.0` to `14.8.0`.

### How to get the detail of each backup method

Details of each backup method are defined in `ActionSet` in KubeBlocks.

To get the `ActionSet` which defines the behavior of backup method named `wal-g-archive` in PostgreSQL, for instance:

```bash
k -n demo get bp pg-cluster-postgresql-backup-policy -oyaml | yq '.spec.backupMethods[] | select(.name=="wal-g-archive") | .actionSetName'
```

ActionSet defined:

- backup type
- both backup and restore procedures
- environment variables used in procedures

## Reference

[^1]: pg_basebackup, <https://www.postgresql.org/docs/current/app-pgbasebackup.html>
[^2]: wal-g <https://github.com/wal-g/wal-g>
[^3]: Internal load balancer: <https://kubernetes.io/docs/concepts/services-networking/service/#internal-load-balancer>
