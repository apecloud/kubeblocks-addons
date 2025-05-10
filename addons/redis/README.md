# Redis on KubeBlocks

Redis is an open source (BSD licensed), in-memory data structure store, used as a database, cache and message broker.

## Features in KubeBlocks

### Supported Topologies

| Topology      | Data Distribution | Scalability | High Availability | Use Cases                     |
|---------------|-------------------|-------------|--------------------|-------------------------------|
| **Standalone**| Single node       | No          | No                 | Development/testing, small datasets |
| **Replication** with sentinel     | Primary-Secondary replication | Read scaling | Yes | Read-heavy workloads, data redundancy needed |
| **Cluster**   | Sharded storage   | Read/write scaling | Yes | Large datasets, high-concurrency production environments |

### Cluster Management Operations

| Operation | Description | Standalone | Replication | Cluster |
|-----------|----------------------|--------------|--------------|--------------|
| **Restart** |• Ordered sequence (followers first)<br/>• Health checks between restarts | Yes | Yes | Yes |
| **Stop/Start** | • Graceful shutdown<br/>• Fast startup from persisted state  | No | Yes | Yes |
| **Horizontal Scaling** | • Adjust replica count dynamically<br/>• Automatic data replication<br/> |Yes | Yes | Yes |
| **Vertical Scaling** |   • Adjust CPU/Memory resources<br/>• Rolling updates for minimal downtime |Yes | Yes | Yes |
| **Volume Expansion** |   • Online storage expansion<br/>• No downtime required |Yes | Yes | Yes |
| **Reconfiguration** |  •Static parameter updates<br/>• Validation rules<br/>• Versioned history |Yes | Yes | Yes |
| **Service Exposure** |  • Multiple exposure types (ClusterIP/NodePort/LB)<br/>• Role-based routing |Yes | Yes | Yes |
| **Switchover** | • Planned primary transfer<br/>• Zero data loss guarantee |N/A | Yes | Yes |

### Backup and Restore

| Feature           | Method          | Description |
|-------------|--------|------------|
| Full Backup | datafile  | uses `redis-cli BGSAVE` command to backup data |
| Continuous Backup | aof | continuously perform incremental backups by archiving Append-Only Files (AOF) |

### Versions

| Major Versions | Description |
|---------------|-------------|
| 7.0           | 7.0.6 |
| 7.2           | 7.2.4, 7.2.7 |

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes Environment**:
   - Cluster v1.21+
   - `kubectl` installed ([Installation Guide](https://kubernetes.io/docs/tasks/tools/))
   - Helm v3+ ([Installation Guide](https://helm.sh/docs/intro/install/))

2. **KubeBlocks Setup**:
   - KubeBlocks installed and running ([Installation](../docs/prerequisites.md))
   - Redis Addon enabled ([Addon Setup](../docs/install-addon.md))

3. **Namespace Setup**:
   Create an isolated namespace for this tutorial:

  ```bash
  kubectl create ns demo
  ```

## Lifecycle Management Operations

### Cluster Provisioning

#### Quick Start

A Redis **replication** cluster has two components, one for Redis, and one for Redis Sentinel[^1].

> [!NOTE]
> For optimal reliability, you should run at least **three** Redis Sentinel replicas.
> Having three or more Sentinels ensures a quorum can be reached during failover decisions, maintaining the high availability of your Redis deployment.

```yaml
# cat examples/redis/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: redis-replication
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
  clusterDef: redis
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  topology: replication
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: redis
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [7.0.6,7.2.4]
      serviceVersion: "7.2.4"
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
    - name: redis-sentinel
      replicas: 3
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
kubectl apply -f examples/redis/cluster.yaml
```

And you will see the Redis cluster status goes `Running` after a while:

```bash
kubectl get cluster redis-replication -w -n demo
```

<details open>
<summary>Expected Output</summary>

```bash
NAME                CLUSTER-DEFINITION   TERMINATION-POLICY   STATUS    AGE
redis-replication   redis                Delete               Running   2m36s
```

</details>

and two Redis replicas are `Running` with roles `primary`,  `secondary` separately. To check the roles of the replicas, you can use following command:

```bash
kubectl get po -l  app.kubernetes.io/instance=redis-replication,apps.kubeblocks.io/component-name=redis -L kubeblocks.io/role -n demo
```

<details open>
<summary>Expected Output</summary>

```bash
NAME                        READY   STATUS    RESTARTS   AGE     ROLE
redis-replication-redis-0   3/3     Running   0          4m36s   primary
redis-replication-redis-1   3/3     Running   0          4m13s   secondary
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
    - name: redis
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      serviceVersion: "7.2.7" # more Redis versions will be supported in the future
```

The list of supported versions can be found by following command:

```bash
kubectl get cmpv redis
```

<details open>
<summary>Expected Output</summary>

```bash
NAME    VERSIONS            STATUS      AGE
redis   7.2.7,7.2.4,7.0.6   Available   5d
```

</details>

### Create Standalone Redis

To create a standalone redis:

```yaml
# cat examples/redis/cluster-standalone.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: redis-standalone
  namespace: demo
spec:
  terminationPolicy: Delete
  clusterDef: redis
  topology: standalone # set topology to standalone
  componentSpecs:
  - name: redis
    replicas: 1       # set replica to 1
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
```

```bash
kubectl apply -f examples/redis/cluster-standalone.yaml
```

It creates one redis component with only one replicas.

### Create Redis with Proxy

To create a redis with a proxy (Twemproxy) in front of it:

```yaml
# cat examples/redis/cluster-twemproxy.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: redis-replication-with-proxy
  namespace: demo
spec:
  terminationPolicy: Delete
  clusterDef: redis
  topology: replication-twemproxy  # set topology to replication-twemproxy
  componentSpecs:
  - name: redis
    replicas: 2
    disableExporter: true
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
  - name: redis-sentinel
    replicas: 3
    resources:
      limits:
        cpu: "0.2"
        memory:  "0.2Gi"
      requests:
        cpu: "0.2"
        memory:  "0.2Gi"
    volumeClaimTemplates:
      - name: data
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 20Gi
  - name: redis-twemproxy       # add one componet on provisioniing: twemproxy
    replicas: 3
    resources:
      limits:
        cpu: "0.2"
        memory: "0.2Gi"
      requests:
        cpu: "0.2"
        memory: "0.2Gi"
```

```bash
kubectl apply -f examples/redis/cluster-twemproxy.yaml
```

A cluster named `redis-twemproxy` will be created with three components, one for Redis (2 replicas), one for Sentinel (3 replicas), and one for twemproxy (3 replicas).

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  terminationPolicy: Delete
  clusterDef: redis
  topology: replication-twemproxy
  componentSpecs:
  - name: redis
  - name: redis-sentinel
  - name: redis-twemproxy       # add one componet on provisioniing: twemproxy
    replicas: 3                 # set the desired number of replicas for twemproxy
    resources:
```

### Create Redis with Multiple Shards

To create a redis sharding cluster (An official distributed Redis)  with 3 shards and 2 replica for each shard:

```yaml
# cat examples/redis/cluster-sharding.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: redis-sharding
  namespace: demo
spec:
  terminationPolicy: Delete
  # Specifies a list of ShardingSpec objects that configure the sharding topology for components of a Cluster. Each ShardingSpec corresponds to a group of components organized into shards, with each shard containing multiple replicas. Components within a shard are based on a common ClusterComponentSpec template, ensuring that all components in a shard have identical configurations as per the template. This field supports dynamic scaling by facilitating the addition or removal of shards based on the specified number in each ShardingSpec. Note: `shardingSpecs` and `componentSpecs` cannot both be empty; at least one must be defined to configure a cluster. ShardingSpec defines how KubeBlocks manage dynamic provisioned shards. A typical design pattern for distributed databases is to distribute data across multiple shards, with each shard consisting of multiple replicas. Therefore, KubeBlocks supports representing a shard with a Component and dynamically instantiating Components using a template when shards are added. When shards are removed, the corresponding Components are also deleted.
  shardings:
    # Represents the common parent part of all shard names. This identifier is included as part of the Service DNS name and must comply with IANA service naming rules. It is used to generate the names of underlying Components following the pattern `$(shardingSpec.name)-$(ShardID)`. ShardID is a random string that is appended to the Name to generate unique identifiers for each shard. For example, if the sharding specification name is "my-shard" and the ShardID is "abc", the resulting component name would be "my-shard-abc". Note that the name defined in component template(`shardingSpec.template.name`) will be disregarded when generating the component names of the shards. The `shardingSpec.name` field takes precedence.
  - name: shard
    # Specifies the desired number of shards. Users can declare the desired number of shards through this field. KubeBlocks dynamically creates and deletes Components based on the difference between the desired and actual number of shards. KubeBlocks provides lifecycle management for sharding, including: - Executing the postProvision Action defined in the ComponentDefinition when the number of shards increases. This allows for custom actions to be performed after a new shard is provisioned. - Executing the preTerminate Action defined in the ComponentDefinition when the number of shards decreases. This enables custom cleanup or data migration tasks to be executed before a shard is terminated. Resources and data associated with the corresponding Component will also be deleted.
    # The number of shards should be no less than 3
    shards: 3
    # The template for generating Components for shards, where each shard consists of one Component. This field is of type ClusterComponentSpec, which encapsulates all the required details and definitions for creating and managing the Components. KubeBlocks uses this template to generate a set of identical Components or shards. All the generated Components will have the same specifications and definitions as specified in the `template` field. This allows for the creation of multiple Components with consistent configurations, enabling sharding and distribution of workloads across Components.
    template:
      name: redis
      componentDef: redis-cluster-7
      disableExporter: true
      replicas: 2
      resources:
        limits:
          cpu: '1'
          memory: 1.1Gi
        requests:
          cpu: '1'
          memory: 1.1Gi
      # Specifies the version of the Component service. This field is used to determine the version of the service that is created for the Component. \
      # The serviceVersion is used to determine the version of the Redis Sharding Cluster kernel. If the serviceVersion is not specified, the default value is the ServiceVersion defined in ComponentDefinition.
      serviceVersion: 7.2.4
      # Component-level services override services defined in referenced ComponentDefinition and expose
      # endpoints that can be accessed by clients
      # This example explicitly override the svc `redis-advertised` to use the NodePort
      # This is a per-pod svc.
      services:
      - name: redis-advertised
        podService: true
        #  - NodePort
        #  - LoadBalancer
        serviceType: NodePort
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
kubectl apply -f examples/redis/cluster-sharding.yaml
```

You may change the number of shards and replicas in the yaml file.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  shardings:
  - name: shard
    shards: 3  # set the desired number of shards.
    template:
      name: redis
      componentDef: redis-cluster-7
      replicas: 2 # set the desired number of replicas for each shard.
      serviceVersion: 7.2.4
      # Component-level services override services defined in
      # referenced ComponentDefinition and expose
      # endpoints that can be accessed by clients
      # This example explicitly override the svc `redis-advertised` to use the NodePort
      services:
      - name: redis-advertised # This is a per-pod svc, and will be used to parse advertised endpoints
        podService: true
        #  - NodePort
        #  - LoadBalancer
        serviceType: NodePort
  ...
```

In this example we demonstrate how to create a Redis Cluster with multiple shards, and how to override the service type of the `redis-advertised` service to `NodePort`.

The service `redis-advertised` is defined in `ComponentDefinition` and will used to parse the advertised endpoints of the Redis pods.

By default, the service type is `NodePort`. If you want to expose the service, you can override the service type to `NodePort` or `LoadBalancer` depending on your need.

Similarly to add or remove shards, you can update the `shardings` field in the `Cluster` resource.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  shardings:
  - name: shard
    shards: 3 # increase or decrease the number of shards.
    template:
      name: redis
      componentDef: redis-cluster-7
      replicas: 2
      serviceVersion: 7.2.4
```

### Cluster Restart

Restart Redis component only,

```yaml
# cat examples/redis/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: redis

```

```bash
kubectl apply -f examples/redis/restart.yaml
```

This operation restart only one component (Redis), as specified in

```yaml
  restart:
  - componentName: redis
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

```yaml
# cat examples/redis/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  type: Stop

```

```bash
kubectl apply -f examples/redis/stop.yaml
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
    - name: redis
      stop: true  # Set to true to stop the component
      replicas: 2
    - name: redis-sentinel
      stop: true  # Set to true to stop the component
      replicas: 3
```

#### Starting the Cluster

Start the cluster from its stopped state:

**Start via OpsRequest**

```yaml
# cat examples/redis/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  type: Start

```

```bash
kubectl apply -f examples/redis/start.yaml
```

**Start via Cluster API**

Update the cluster spec directly:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: redis
      stop: false  # Set to false to start the component or remove the field (default to false)
      replicas: 2
    - name: redis-sentinel
      stop: false  # Set to false to start the component or remove the field (default to false)
      replicas: 3
```

## Scaling Operations

### Horizontal Scaling

#### Scale Out Operation

Add a new replica to the cluster:

```yaml
# cat examples/redis/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: redis
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/redis/scale-out.yaml
```

To Check detailed operation status

```bash
kubectl describe ops -n demo redis-scale-out
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
kubectl get pods -n demo -l app.kubernetes.io/instance=redis-replication -L kubeblocks.io/role
```

### Scale In Operation

> [!NOTE]
> If the replica being scaled-in happens to be the primary replicas, KubeBlocks will trigger a SwitchOver action (if defined).

#### Standard Scale In Operation

Remove a replica from the cluster:

```yaml
# cat examples/redis/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: redis
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/redis/scale-in.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo redis-scale-in
```

**Expected Workflow**:

1. Selected replica (the one with the largest ordinal) is removed
2. Pod is terminated gracefully
3. Cluster status changes from `Updating` to `Running`

**Verification**:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=redis-replication
```

#### Targeted Instance Scale In

For cases where you need to take a specific problematic replica offline for maintenance:

```yaml
# cat examples/redis/scale-in-specified-pod.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-scale-in-specified-pod
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: redis
    # Specifies the replica changes for scaling out components
    scaleIn:
      # Specifies the instance names that need to be taken offline
      onlineInstancesToOffline:
        - 'redis-replication-redis-1'

```

```bash
kubectl apply -f examples/redis/scale-in-specified-pod.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo redis-scale-in-specified-pod
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
    name: redis
    offlineInstances:
      - redis-replication-redis-1  # the instance name specified in opsrequest
    replicas: 1  # replicas reduced by one at the same time.
```

#### Horizontal Scaling via Cluster API

Directly update replica count via Cluster API:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: redis
      replicas: 2  # Adjust replicas for scaling in and out.
      offlineInstances:
        - redis-replication-redis-1 # for targetd-instance scale-in scenario, default to empty list.
```

### Vertical Scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:

- CPU cores/processing power
- Memory (RAM)

#### Vertical Scaling via OpsRequest API

Perform vertical scaling on Redis Component using a operation request:

```yaml
# cat examples/redis/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: redis
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/redis/verticalscale.yaml
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
    - name: redis
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

| Type | Restart Required | Scope |
|------|------------------|-------|
| **Dynamic** | No | Immediate effect |
| **Static** | Yes | After restart |

> [!IMPORTANT]
> So far, Redis Addons does not implement any dynamic reload action for `Dynamic Parameters`, thus changes on any parameters will cause a restart.

### Reconfiguration

1. **Apply Changes**:

```yaml
# cat examples/redis/reconfigure-aof.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-reconfigure-aof
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: redis
    parameters:
      # Represents the name of the parameter that is to be updated.
    - key: aof-timestamp-enabled
      value: 'yes'
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring
```

```bash
kubectl apply -f examples/redis/reconfigure-aof.yaml
```

2. **Monitor Progress**:

```bash
kubectl describe ops redis-reconfiguring -n demo  # check opsrequest progress
kubectl describe parameter redis-reconfiguring -n demo  # check parameters reconfigurion details
```

3. **Verify Changes**:

```sql
-- login to redis and check configs
127.0.0.1:6379> CONFIG GET aof-timestamp-enabled
1) "aof-timestamp-enabled"
2) "yes"
```

> [!IMPORTANT]
>
> - Static changes trigger rolling restarts
> - Monitor cluster health during reconfiguration

4. **Trouble Shooting**

```bash
kubectl describe ops redis-reconfiguring -n demo  # check opsrequest progress
kubectl describe parameter redis-reconfiguring -n demo  # check parameters reconfigurion details
```

## High Availability

### Switchover (Planned Primary Transfer)

SwitchOver is a controlled operation that safely transfers leadership while maintaining:

- Continuous availability
- Zero data loss
- Minimal performance impact

<details>
<summary>Developer: Switchover Actions</summary>
KubeBlocks executes SwitchOver actions defined in `componentdefinition.spec.lifecycleActions.switchover`.

To get the SwitchOver actions for Redis:

```bash
kubectl get cmpd redis-7-1.0.0-alpha.0 -oyaml | yq '.spec.lifecycleActions.switchover'
```

</details>

#### Prerequisites

- Cluster must be in `Running` state
- No ongoing maintenance operations

#### Switchover Types

1. **Automatic Switchover** (No preferred candidate):

```yaml
# cat examples/redis/switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-switchover
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: redis
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: redis-replication-redis-0

```

   ```bash
   kubectl apply -f examples/redis/switchover.yaml
   ```

2. **Targeted Switchover** (Specific instance):

```yaml
# cat examples/redis/switchover-specified-instance.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-switchover-specified-2-1
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: redis
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: redis-replication-redis-2
    # If CandidateName is specified, the role will be transferred to this instance.
    # The name must match one of the pods in the component.
    # Refer to ComponentDefinition's Swtichover lifecycle action for more details.
    candidateName: redis-replication-redis-1
```

   ```bash
   kubectl apply -f examples/redis/switchover-specified-instance.yaml
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
  kubectl get events -n demo --field-selector involvedObject.name=redis-replication
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
# cat examples/redis/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: redis
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/redis/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=redis-replication -n demo
```

#### Volume Expansion via Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: redis
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
# cat examples/redis/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-expose-enable
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: redis
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
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Expose

```

```bash
kubectl apply -f examples/redis/expose-enable.yaml
```

- Disable Service

```yaml
# cat examples/redis/expose-disable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-expose-disable
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: redis
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
kubectl apply -f examples/redis/expose-disable.yaml
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
      componentSelector: redis
      name: redis-vpc
      serviceName: redis-vpc
      roleSelector: primary  # [primary, secondary] for Redis
      spec:
        ipFamilyPolicy: PreferDualStack
        ports:
        - name: redis
          port: 3306
          protocol: TCP
          targetPort: redis
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
   kubectl get backuppolicy -n demo -l app.kubernetes.io/instance=redis-replication
   ```

2. **View default BackupSchedule**:

   ```bash
   kubectl get backupschedule -n demo -l app.kubernetes.io/instance=redis-replication
   ```

#### Full Backup: datafile

The `datafile` method uses redis `BGSAVE` command to perform a full backup and  upload backup file using `datasafed push`

1. **On-Demand Backup**:

```yaml
# cat examples/redis/backup.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: redis-backup-datafile
  namespace: demo
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - datafile
  # - volume-snapshot
  # - aof
  backupMethod: datafile
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: redis-replication-redis-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete

```

   ```bash
   kubectl apply -f examples/redis/backup.yaml
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

#### Continuous Backup: aof

Redis Append Only Files(AOFs) record every write operation received by the server, in the order they were processed, which allows Redis to reconstruct the dataset by replaying these commands.
KubeBlocks supports continuous backup for the Redis component by archiving Append-Only Files (AOF). It will process incremental AOF files, update base AOF file, purge expired files and save backup status (records metadata about the backup process, such as total size and timestamps, to the `Backup` resource).

Before enabling a continuous backup, you must set variable `aof-timestamp-enabled` to `yes`, as introduced in [Reconfiguration](#reconfiguration) section.

```yaml
# cat examples/redis/reconfigure-aof.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: redis-reconfigure-aof
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: redis-replication
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: redis
    parameters:
      # Represents the name of the parameter that is to be updated.
    - key: aof-timestamp-enabled
      value: 'yes'
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring
```

```bash
kubectl apply -f examples/redis/reconfigure-aof.yaml
```

> [!IMPORTANT]
> Once `aof-timestamp-enabled` is on, Redis will include timestamp in the AOF file.
> It may have following side effects: storage overhead, performance overhead (write latency).
> It is not recommended to enable this feature when you have high write throughput, or you have limited storage space.

#### Scheduled Backups

Update `BackupSchedule` to schedule enable(`enabled`) backup methods and set the time (`cronExpression`) to your need:

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
spec:
  backupPolicyName: redis-replication-redis-backup-policy
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
  - backupMethod: aof
    cronExpression: '*/30 * * * *'
    enabled: true   # set to `true` to enable continuous backup
    name: aof
    retentionPeriod: 8d # by default, retentionPeriod of continuous backup is 1d more than that of a full backup.
```

#### Troubleshooting

- **Backup Stuck**:

  ```bash
  kubectl describe backup <name> -n demo  # describe backup
  kubectl get po -n demo -l app.kubernetes.io/instance=redis-replication,dataprotection.kubeblocks.io/backup-policy=redis-replication-redis-backup-policy # get list of pods working for Backups
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
   kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Full,app.kubernetes.io/instance=redis-replication # get the list of full backups
   ```

2. **Prepare Credentials**:

   ```bash
   # Get encrypted system accounts
    kubectl get backup <backupName> -n demo -ojson | jq -r '.metadata.annotations | ."kubeblocks.io/encrypted-system-accounts" | fromjson .redis | tojson |gsub("\""; "\\"")'
   ```

3. **Configure Restore**:
   Update `examples/redis/restore.yaml` with:
   - Backup name and namespace: from step 1
   - Encrypted system accounts: from step 2
   - Target cluster configuration

4. **Execute Restore**:

```yaml
# cat examples/redis/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: redis-replication-restore
  namespace: demo
  annotations:
    # NOTE: replace <ENCRYPTED-SYSTEM-ACCOUNTS> with the accounts info from your backup
    # NOTE: replace <BACKUP_NAME> with your backup
    kubeblocks.io/restore-from-backup: '{"redis":{"encryptedSystemAccounts":"<ENCRYPTED-SYSTEM-ACCOUNTS>","name":"<BACKUP_NAME>","namespace":"demo","volumeRestorePolicy":"Parallel"}}'
spec:
  terminationPolicy: Delete
  clusterDef: redis
  topology: replication
  componentSpecs:
    - name: redis
      serviceVersion: "7.2.4"
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
    - name: redis-sentinel
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
   kubectl apply -f examples/redis/restore.yaml
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
  kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Continuous,app.kubernetes.io/instance=redis-replication  # get the list of Continuous backups
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
  kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Full,app.kubernetes.io/instance=redis-replication  # get the list of Full backups
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
  kubectl get backup <backup-name> -n demo -ojson | jq -r '.metadata.annotations | ."kubeblocks.io/encrypted-system-accounts" | fromjson .redis | tojson |gsub("\""; "\\"")'
  ```

3. **Configure Restore**:
   Update `examples/redis/restore-pitr.yaml` with:
   - Backup name and namespace: from step 1
   - Point time: falls in `timeRange` from Step 1
   - Encrypted system accounts: from step 2
   - Target cluster configuration

4. **Execute Restore**:

```yaml
# cat examples/redis/restore-pitr.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: redis-restore-pitr
  namespace: demo
  annotations:
    # NOTE: replace <ENCRYPTED-SYSTEM-ACCOUNTS> with the accounts info from you backup
    # NOTE: replace <CONTINUOUS_BACKUP_NAME> with the continuouse backup name
    # NOTE: replace <RESTORE_POINT_TIME>  with a valid time within the backup timeRange.
    kubeblocks.io/restore-from-backup: '{"redis":{"encryptedSystemAccounts":"{\"default\":\"R+YMeDpvPfHxiZVxy2RV1LK0CSTslsUeOOic9BIqOs0jJvA6ndg=\"}","name":"209bb55a-redis-replication-red-aof","namespace":"demo","restoreTime":"2025-05-10T04:57:29Z","volumeRestorePolicy":"Parallel"}}'
spec:
  terminationPolicy: Delete
  clusterDef: redis
  topology: replication
  componentSpecs:
    - name: redis
      serviceVersion: "7.2.4"
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
    - name: redis-sentinel
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
   kubectl apply -f examples/redis/restore-pitr.yaml
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
    - create a Redis Cluster with exporter running as sidecar (`disableExporter: false`)
    - Skip if already created

### Metrics Collection Setup

#### 1. Configure PodMonitor

1. **Get Exporter Details**:

   ```bash
   kubectl get po -n demo redis-replication-redis-0 -oyaml |  yq '.spec.containers[] | select(.name=="metrics") | .ports'
   ```

  <details open>
  <summary>Expected Output:</summary>

   ```text
  - containerPort: 9121
    name: http-metrics
    protocol: TCP
   ```

  </details>

2. **Verify Metrics Endpoint**:

   ```bash
   kubectl -n demo exec -it pods/redis-replication-redis-0 -c metrics -- \
     curl -s http://127.0.0.1:9121/metrics | head -n 50
   ```

3. **Apply PodMonitor**:

```yaml
# cat examples/redis/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: redis-replication-pod-monitor
  namespace: demo
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
      app.kubernetes.io/instance: redis-replication
      apps.kubeblocks.io/component-name: redis
```

   ```bash
   kubectl apply -f examples/redis/pod-monitor.yaml
   ```

#### 2. Grafana Dashboard Setup

1. **Import Dashboard**:
   - URL: [Redis Dashboard](https://raw.githubusercontent.com/apecloud/kubeblocks-addons/refs/heads/main/addons/redis/dashboards/redis.json)

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
kubectl patch cluster -n demo redis-replication \
  -p '{"spec":{"terminationPolicy":"WipeOut"}}' \
  --type="merge"
```

2. Verify the termination policy was updated:

```bash
kubectl get cluster -n demo redis-replication -o jsonpath='{.spec.terminationPolicy}'
```

3. Delete the cluster:

```bash
kubectl delete cluster -n demo redis-replication
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

### Connecting to Redis

To connect to the Redis cluster, you can:

- port forward the Redis service to your local machine:

```bash
kubectl port-forward svc/redis-replication-redis 6379:6379 -n demo
```

- or expose the Redis service to the internet, as mentioned in the [Networking](#networking) section.

Then you can connect to the Redis cluster with the following command:

```bash
redis-cli -h <endpoint> -p 6379 -a <defaultUserPasswd>
```

and credentials can be found in the `secret` resource:

```bash
userName=$(kubectl get secret -n demo redis-replication-redis-account-default -ojsonpath='{.data.username}' | base64 -d)
defaultUserPasswd=$(kubectl get secret -n demo redis-replication-redis-account-default -ojsonpath='{.data.password}' | base64 -d)
```

#### Why Redis Sentinel starts before Redis

Redis Sentinel is a high availability solution for Redis. It provides monitoring, notifications, and automatic failover for Redis instances.

Each Redis replica, from the Redis component, upon startup, will connect to the Redis Sentinel instances to get the current leader and follower information. It needs to determine:

- Whether it should act as the primary (master) node.
- If not, which node is the current primary to replicate from.

In more detail, each Redis replica will:

1. Check for Existing Primary Node
    - Queries Redis Sentinel to find out if a primary node is already elected.
    - Retrieve the primary's address and port.
1. Initialize as Primary if Necessary
    - If no primary is found (e.g., during initial cluster setup), it configures the current Redis instance to become the primary.
    - Updates Redis configuration to disable replication.
1. Configure as Replica if Primary Exists
    - If a primary is found, it sets up the current Redis instance as a replica.
    - Updates the Redis configuration with the `replicaof` directive pointing to the primary's address and port.
    - Initiates replication to synchronize data from the primary.

KubeBlocks ensures that Redis Sentinel starts first to provide the necessary information for the Redis replicas to initialize correctly. Such dependency is well-expressed in the KubeBlocks CRD `ClusterDefinition` ensuring the correct startup order.

More details on how components for the `replication` topology are started, upgraded can be found in:

```bash
kubectl get cd redis -oyaml | yq '.spec.topologies[] | select(.name=="replication") | .orders'
```

### How to override default Service Type

There are cases when default service type does not meet you need. To override these default service's types, you may :

1. check the list of services defined for each component

```bash
kubectl get cmpd redis-cluster-7-1.0.0-alpha.0 -oyaml | yq '.spec.services'
```

<details open>
<summary>Expected Output</summary>

In redis cluster, this is a per-pod service and will be used to parse advertised endpoints

```yaml
- disableAutoProvision: true  # disabled by default
  name: redis-advertised
  podService: true            # podService: true  means this is a per-pod svc
  serviceName: redis-advertised
  spec:
    ports:
      - name: redis-advertised
        port: 6379
        protocol: TCP
        targetPort: redis-cluster
      - name: advertised-bus
        port: 16379
        protocol: TCP
        targetPort: cluster-bus
    type: NodePort           # default service type is NodePort
```

</details>

To override this service type when creating cluster, you may override service by `name`:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  shardings:
  - name: shard
    shards: 3  # set the desired number of shards.
    template:
      name: redis
      componentDef: redis-cluster-7
      replicas: 2 # set the desired number of replicas for each shard.
      serviceVersion: 7.2.4
      # Component-level services override services defined in
      # referenced ComponentDefinition and expose
      # endpoints that can be accessed by clients
      # This example explicitly override the svc `redis-advertised` to use the LoadBalancer
      services:
      - name: redis-advertised # This is a per-pod svc, and will be used to parse advertised endpoints
        podService: true
        #  - NodePort
        #  - LoadBalancer
        serviceType: LoadBalancer
  ...
```

In this example we demonstrate how to create a Redis Cluster with multiple shards, and how to override the service type of the `redis-advertised` service to `NodePort`.

The service `redis-advertised` is defined in `ComponentDefinition` and will used to parse the advertised endpoints of the Redis pods.

By default, the service type is `NodePort`. If you want to expose the service, you can override the service type to `NodePort` or `LoadBalancer` depending on your need.

### How to Scale Shards

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  shardings:
  - name: shard
    shards: 3 # increase or decrease the number of shards.
    template:
      name: redis
      componentDef: redis-cluster-7
      replicas: 2 # set the desired number of replicas for each shard.
      serviceVersion: 7.2.4
      stop: false # set to `true` to stop all components
```

### List of K8s Resources created when creating an Redis Cluster

To get the full list of associated resources created by KubeBlocks for given cluster:

```bash
kubectl get cmp,its,po -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # cluster and worload
kubectl get backuppolicy,backupschedule,backup -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # data protection resources
kubectl get componentparameter,parameter -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # configuration resources
kubectl get opsrequest -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # opsrequest resources
kubectl get svc,secret,cm,pvc -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # k8s native resources
```

## References

[^1]: Redis Sentinel: <https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/>
