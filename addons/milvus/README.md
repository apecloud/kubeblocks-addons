# Milvus on KubeBlocks

## Overview

Milvus is an open source (Apache-2.0 licensed) vector database built to power embedding similarity search and AI applications. Milvus's architecture is designed to handle large-scale vector datasets and includes various deployment modes:  Milvus Standalone, and Milvus Distributed, to accommodate different data scale needs.

## Features in KubeBlocks

### Supported Topologies

Milvus supports two deployment modes to accommodate different scale requirements:

#### Standalone Mode

A lightweight deployment suitable for development and testing:

- **Milvus Core**: Provides vector search and database functionality
- **Metadata Storage (ETCD)**: Stores cluster metadata and configuration
- **Object Storage (MinIO/S3)**: Persists vector data and indexes

#### Cluster Mode

A distributed deployment for production workloads with multiple specialized components:

**Access Layer**

- Stateless proxies that handle client connections and request routing

**Compute Layer**

- Query Nodes: Execute search operations
- Data Nodes: Handle data ingestion and compaction
- Index Nodes: Build and maintain vector indexes

**Coordination Layer**

- Root Coordinator: Manages global metadata
- Query Coordinator: Orchestrates query execution
- Data Coordinator: Manages data distribution
- Index Coordinator: Oversees index building

**Storage Layer**

- Metadata Storage (ETCD): Cluster metadata and configuration
- Object Storage (MinIO/S3): Persistent vector data storage
- Log Storage (Pulsar): Message queue for change data capture

### Cluster Management Operations

| Operation | Description | Standalone | Cluster |
|-----------|----------------------|------------|---------|
| **Restart** | • Ordered sequence (followers first)<br/>• Health checks between restarts | YES | YES |
| **Stop/Start** | • Graceful shutdown<br/>• Fast startup from persisted state | YES | YES |
| **Horizontal Scaling** | • Adjust replica count dynamically<br/>• Automatic data replication<br/> | YES | YES |
| **Vertical Scaling** | • Adjust CPU/Memory resources<br/>• Rolling updates for minimal downtime<br/> | YES | YES |
| **Volume Expansion** | • Online storage expansion<br/>• No downtime required | N/A | N/A |
| **Reconfiguration** | • Dynamic/Static parameter updates<br/>• Validation rules<br/>• Versioned history | NO | NO |
| **Service Exposure** | • Multiple exposure types (ClusterIP/NodePort/LB)<br/>• Role-based routing | YES | YES |
| **Switchover** | • Planned primary transfer<br/>• Zero data loss guarantee | N/A | N/A |

### Data Protection

| Type       | Method     | Details |
|------------|------------|---------|
| N/A | N/A | N/A |

### Supported Versions

| Versions |
|----------|
| 2.3.2 |

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes Environment**:
   - Cluster v1.21+
   - `kubectl` installed ([Installation Guide](https://kubernetes.io/docs/tasks/tools/))
   - Helm v3+ ([Installation Guide](https://helm.sh/docs/intro/install/))

2. **KubeBlocks Setup**:
   - KubeBlocks installed and running ([Installation](../docs/prerequisites.md))
   - **ETCD** , **Milvus** , **Pulsar** Addons Enabled, refer to [Install Addons](../docs/install-addon.md)

3. **Namespace Setup**:
   Create an isolated namespace for this tutorial:

  ```bash
  kubectl create ns demo
  ```

## Lifecycle Management Operations

### Cluster Provisioning

#### Quick Start (Standalone Mode)

Create a Milvus cluster of `Standalone` mode:

```yaml
# cat examples/milvus/cluster-standalone.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: milvus-standalone
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
  # The value must be `milvus` to create a Milvus Cluster
  clusterDef: milvus
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  # Valid options are: [standalone,cluster]
  topology: standalone
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: etcd
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
                storage: 10Gi
    - name: minio
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
                storage: 10Gi
    - name: milvus
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
                storage: 10Gi

```

```bash
kubectl apply -f examples/milvus/cluster-standalone.yaml
```

This will create a standalone Milvus cluster with the following components: Milvus, Metadata Storage (ETCD), Object Storage (minio), and Milvus will not be created until the ETCD and Minio are ready.

To access the Milvus service, you can expose the service by creating a service:

```bash
kubectl port-forward pod/milvus-standalone-milvus-0 -n demo 19530:19530
```

And then you can access the Milvus service via `localhost:19530`.

#### Cluster Mode

TO create a Milvus cluster of `Cluster` mode, it is recommended to create one etcd cluster and one minio cluster before hand for Storage.

```yaml
# cat examples/milvus/etcd-cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: etcdm-cluster
  namespace: demo
spec:
  terminationPolicy: WipeOut
  componentSpecs:
    - name: etcd
      componentDef: etcd-3-1.0.0
      serviceVersion: 3.5.6
      replicas: 1
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
kubectl apply -f examples/milvus/etcd-cluster.yaml  # for metadata storage
kubectl apply -f examples/milvus/minio-cluster.yaml # for object storage
kubectl apply -f examples/milvus/pulsar-cluster.yaml # for log storage
```

Create a Milvus cluster with `Cluster` mode:

```yaml
# cat examples/milvus/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  namespace: demo
  name: milvus-cluster
spec:
  # Specifies the behavior when a Cluster is deleted.
  # Valid options are: [DoNotTerminate, Delete, WipeOut] (`Halt` is deprecated since KB 0.9)
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies the name of the ClusterDefinition to use when creating a Cluster.
  # Note: DO NOT UPDATE THIS FIELD
  # The value must be `milvus` to create a Milvus Cluster
  clusterDef: milvus
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  # Valid options are: [standalone,cluster]
  topology: cluster
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: proxy
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      # Defines a list of ServiceRef for a Component
      serviceRefs:
        - name: milvus-meta-storage # Specifies the identifier of the service reference declaration, defined in `componentDefinition.spec.serviceRefDeclarations[*].name`
          namespace: demo        # namepspace of referee cluster, update on demand
          # References a service provided by another KubeBlocks Cluster
          clusterServiceSelector:
            cluster: etcdm-cluster  # ETCD Cluster Name, update the cluster name on demand
            service:
              component: etcd       # component name, should be etcd
              service: headless     # Refer to default headless Service
              port: client          # Refer to port name 'client'
        - name: milvus-log-storage
          namespace: demo
          clusterServiceSelector:
            cluster: pulsarm-cluster # Pulsar Cluster Name
            service:
              component: broker
              service: headless
              port: pulsar
        - name: milvus-object-storage
          namespace: demo
          clusterServiceSelector:
            cluster: miniom-cluster # Minio Cluster Name
            service:
              component: minio
              service: headless
              port: http
            credential:            # Specifies the SystemAccount to authenticate and establish a connection with the referenced Cluster.
              component: minio     # for component 'minio'
              name: admin          # the name of the credential (SystemAccount) to reference, using account 'admin' in this case
    - name: mixcoord
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      serviceRefs:
        - name: milvus-meta-storage
          namespace: demo
          clusterServiceSelector:
            cluster: etcdm-cluster
            service:
              component: etcd
              service: headless
              port: client
        - name: milvus-log-storage
          namespace: demo
          clusterServiceSelector:
            cluster: pulsarm-cluster
            service:
              component: broker
              service: headless
              port: pulsar
        - name: milvus-object-storage
          namespace: demo
          clusterServiceSelector:
            cluster: miniom-cluster
            service:
              component: minio
              service: headless
              port: http
            credential:
              component: minio
              name: admin
    - name: datanode
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      serviceRefs:
        - name: milvus-meta-storage
          namespace: demo
          clusterServiceSelector:
            cluster: etcdm-cluster
            service:
              component: etcd
              service: headless
              port: client
        - name: milvus-log-storage
          namespace: demo
          clusterServiceSelector:
            cluster: pulsarm-cluster
            service:
              component: broker
              service: headless
              port: pulsar
        - name: milvus-object-storage
          namespace: demo
          clusterServiceSelector:
            cluster: miniom-cluster
            service:
              component: minio
              service: headless
              port: http
            credential:
              component: minio
              name: admin
    - name: indexnode
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      serviceRefs:
        - name: milvus-meta-storage
          namespace: demo
          clusterServiceSelector:
            cluster: etcdm-cluster
            service:
              component: etcd
              service: headless
              port: client
        - name: milvus-log-storage
          namespace: demo
          clusterServiceSelector:
            cluster: pulsarm-cluster
            service:
              component: broker
              service: headless
              port: pulsar
        - name: milvus-object-storage
          namespace: demo
          clusterServiceSelector:
            cluster: miniom-cluster
            service:
              component: minio
              service: headless
              port: http
            credential:
              component: minio
              name: admin
    - name: querynode
      replicas: 2
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      serviceRefs:
        - name: milvus-meta-storage
          namespace: demo
          clusterServiceSelector:
            cluster: etcdm-cluster
            service:
              component: etcd
              service: headless
              port: client
        - name: milvus-log-storage
          namespace: demo
          clusterServiceSelector:
            cluster: pulsarm-cluster
            service:
              component: broker
              service: headless
              port: pulsar
        - name: milvus-object-storage
          namespace: demo
          clusterServiceSelector:
            cluster: miniom-cluster
            service:
              component: minio
              service: headless
              port: http
            credential:
              component: minio
              name: admin

```

```bash
kubectl apply -f examples/milvus/cluster.yaml
```

The cluster will be created with the following components:

- Proxy
- Data Node
- Index Node
- Query Node
- Mixed Coordinator

And each component will be created with `serviceRef` to the corresponding service: etcd, minio, and pulsar.

```yaml
      # Defines a list of ServiceRef for a Component
      serviceRefs:
        - name: milvus-meta-storage # Specifies the identifier of the service reference declaration, defined in `componentDefinition.spec.serviceRefDeclarations[*].name`
          namespace: demo        # namepspace of referee cluster, update on demand
          # References a service provided by another KubeBlocks Cluster
          clusterServiceSelector:
            cluster: etcdm-cluster  # ETCD Cluster Name, update the cluster name on demand
            service:
              component: etcd       # component name, should be etcd
              service: headless     # Refer to default headless Service
              port: client          # NOTE: Refer to port name 'client', for port number '3501'
        - name: milvus-log-storage
          namespace: demo
          clusterServiceSelector:
            cluster: pulsarm-cluster # Pulsar Cluster Name
            service:
              component: broker
              service: headless
              port: pulsar          # NOTE: Refer to port name 'pulsar', for port number '6650'
        - name: milvus-object-storage
          namespace: demo
          clusterServiceSelector:
            cluster: miniom-cluster # Minio Cluster Name
            service:
              component: minio
              service: headless
              port: http           # NOTE: Refer to port name 'http', for port number '9000'
            credential:            # Specifies the SystemAccount to authenticate and establish a connection with the referenced Cluster.
              component: minio     # for component 'minio'
              name: admin          # NOTE: the name of the credential (SystemAccount) to reference, using account 'admin' in this case
```

> [!NOTE]
> Clusters, such as Pulsar, Minio and ETCD, have multiple ports for different services.
> When creating Cluster with `serviceRef`, you should know which `port` providing corresponding services.

For instance, in MinIO, there are mainly four ports: 9000, 9001, 3501, and 3502, and they are used for different services or functions.

- 9000: This is the default API port for MinIO. Clients communicate with the MinIO server through this port to perform operations such as uploading, downloading, and deleting objects.
- 9001: This is the default console port for MinIO. MinIO provides a web - based management console that users can access and manage the MinIO server through this port.
- 3501: This port is typically used for inter - node communication in MinIO's distributed mode. In a distributed MinIO cluster, nodes need to communicate through this port for data synchronization and coordination.
- 3502: This port is also typically used for inter - node communication in MinIO's distributed mode. Similar to 3501, it is used for data synchronization and coordination between nodes, but it might be for different communication protocols or services.

And you should pick the port, either using port name or port number, provides API service:

```yaml
- name: milvus-object-storage
  namespace: demo
  clusterServiceSelector:
    cluster: miniom-cluster
    service:
      component: minio
      service: headless
      port: http  # set port to the one provides API service in your Minio.
```

To access the Milvus service, you can expose the service by creating a service:

```bash
kubectl port-forward svc/milvus-cluster-proxy -n demo 19530:19530
```

### Cluster Restart

Restart the cluster components with zero downtime:

```yaml
# cat examples/milvus/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: milvus-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: milvus-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
    # - standalone: milvus
    # - standalone: etcd
    # - standalone: minio
    # - distributed: proxy
    # - distributed: mixcoord
    # - distributed: datanode
    # - distributed: indexnode
    # - distributed: querynode
  - componentName: mixcoord

```

```bash
kubectl apply -f examples/milvus/restart.yaml
```

This operation can only be performed via `OpsRequest`, and there is no corresponding CLUSTER API operation - because restart is not a declaration but an action.

### Cluster Stop and Start

#### Stopping the Cluster

Gracefully stop the cluster to conserve resources while retaining all data (PVC). It is ideal for cost savings during inactive periods.

**Stop via OpsRequest**

```yaml
# cat examples/milvus/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: milvus-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: milvus-cluster
  type: Stop
  # Lists Components to be stopped. ComponentOps specifies the Component to be operated on.
  # # The stop field is optional, all components in the cluster will be stopped if not specifed.
  # stop:
  #   # Specifies the name of the Component.
  #   # - standalone: milvus
  #   # - standalone: etcd
  #   # - standalone: minio
  #   # - distributed: proxy
  #   # - distributed: mixcoord
  #   # - distributed: datanode
  #   # - distributed: indexnode
  #   # - distributed: querynode
  #   - componentName: mixcoord

```

```bash
kubectl apply -f examples/milvus/stop.yaml
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
    - name: querynode
      stop: true  # Set to true to stop the component, set it to true for all components to stop them all
      replicas: 2
```

#### Starting the Cluster

Start the cluster from its stopped state:

**Start via OpsRequest**

```yaml
# cat examples/milvus/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: milvus-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: milvus-cluster
  type: Start

```

```bash
kubectl apply -f examples/milvus/start.yaml
```

**Start via Cluster API**

Update the cluster spec directly:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: querynode
      stop: false  # Set to false to start the component or remove the field (default to false), set for all components to start them all
      replicas: 2
```

## Scaling Operations

### Horizontal Scaling

#### Scale Out Operation

Add a new replica to the cluster:

```yaml
# cat examples/milvus/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: milvus-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: milvus-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: querynode
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/milvus/scale-out.yaml
```

To Check detailed operation status

```bash
kubectl describe ops -n demo milvus-scale-out
```

**Expected Workflow**:

1. New pod is provisioned with `Pending` status
2. Component status changes from `Updating` to `Running`
3. Cluster status changes from `Updating` to `Running`

### Scale In Operation

#### Standard Scale In Operation

Remove a replica from the cluster:

```yaml
# cat examples/milvus/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: milvus-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: milvus-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: querynode
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/milvus/scale-in.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo milvus-scale-in
```

**Expected Workflow**:

1. Selected replica (the one with the largest ordinal) is removed
2. Pod is terminated gracefully
3. Cluster status changes from `Updating` to `Running`

#### Targeted Instance Scale In

For cases where you need to take a specific problematic replica offline for maintenance:

```yaml
# cat examples/milvus/scale-in-specified-pod.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: milvus-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: milvus-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: querynode
    # Specifies the replica changes for scaling out components
    scaleIn:
      # Specifies the instance names that need to be taken offline
      onlineInstancesToOffline:
        - 'milvus-cluster-querynode-1'
```

```bash
kubectl apply -f examples/milvus/scale-in-specified-pod.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo milvus-scale-in-specified-pod
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
    name: querynode
    offlineInstances:
      - milvus-cluster-querynode-1  # the instance name specified in opsrequest
    replicas: 1  # note: replicas also reduced by one at the same time.
```

#### Horizontal Scaling via Cluster API

Directly update replica count via Cluster API:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: querynode
      replicas: 2  # Adjust replicas for scaling in and out.
      offlineInstances:
        - milvus-cluster-querynode-1 # for targetd-instance scale-in scenario, default to empty list.
```

### Vertical Scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:

- CPU cores/processing power
- Memory (RAM)

#### Vertical Scaling via OpsRequest API

Perform vertical scaling using a operation request:

```yaml
# cat examples/milvus/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: milvus-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: milvus-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
    # - standalone: milvus
    # - standalone: etcd
    # - standalone: minio
    # - distributed: proxy
    # - distributed: mixcoord
    # - distributed: datanode
    # - distributed: indexnode
    # - distributed: querynode
  - componentName: querynode
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/milvus/verticalscale.yaml
```

#### Vertical Scaling via Cluster API

Directly modify cluster specifications for vertical scaling:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: querynode
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

## Networking

### Expose SVC via Cluster API

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
      componentSelector: proxy
      name: milvus-vpc
      serviceName: milvus-vpc
      spec:
        ipFamilyPolicy: PreferDualStack
        ports:
        - name: milvus
          port: 19530
          protocol: TCP
          targetPort: milvus
        type: LoadBalancer  # [ClusterIP, NodePort, LoadBalancer]
```

### Cloud Provider Load Balancer Annotations

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

## Monitoring & Observability

### Prerequisites

1. **Prometheus Operator**: Required for metrics collection
   - Skip if already installed
   - Install via: [Prometheus Operator Guide](../docs/install-prometheus.md)

2. **Access Credentials**: Ensure you have:
   - `kubectl` access to the cluster
   - Grafana admin privileges (for dashboard import)

### Metrics Collection Setup

#### 1. Configure PodMonitor

1. **Verify Metrics Endpoint**:

   ```bash
   kubectl -n demo exec -it pods/milvus-cluster-proxy-0 -- \
     curl -s http://127.0.0.1:9091/metrics | head -n 50
   ```

   Perform the verification against all Milvus replicas, including:
    - milvus-cluster-datanode-{id}
    - milvus-cluster-indexnode-{id}
    - milvus-cluster-mixcoord-{id}
    - milvus-cluster-proxy-{id}
    - milvus-cluster-querynode-{id}

3. **Apply PodMonitor**:

```yaml
# cat examples/milvus/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: milvus-cluster-pod-monitor
  namespace: demo
  labels:               # this is labels set in `prometheus.spec.podMonitorSelector`
    release: prometheus
spec:
  podMetricsEndpoints:
    - path: /metrics
      port: metrics
      scheme: http
      relabelings:
        - targetLabel: app_kubernetes_io_name
          replacement: milvus
  namespaceSelector:
    matchNames:
      - demo
  selector:
    matchLabels:
      app.kubernetes.io/instance: milvus-cluster # cluster name: milvus-cluster
```

   ```bash
   kubectl apply -f examples/milvus/pod-monitor.yaml
   ```

  It sets up the `PodMonitor` to monitor the Milvus cluster and scrapes the metrics from the Milvus components.

  ```yaml
    podMetricsEndpoints:
      - path: /metrics
        port: metrics
        scheme: http
        relabelings:
          - targetLabel: app_kubernetes_io_name
            replacement: milvus # add a label to the target: app_kubernetes_io_name=milvus
  ```

  For more information about the metrics, refer to the [Visualize Milvus Metrics](https://milvus.io/docs/visualize.md).

#### 2. Grafana Dashboard Setup

1. **Import Dashboard**:
   - URL: [Milvus Dashboard](https://raw.githubusercontent.com/milvus-io/milvus/refs/heads/master/deployments/monitor/grafana/milvus-dashboard.json)
   - for more details please refer to [Visualize metrics using Grafana](https://milvus.io/docs/visualize.md)

2. **Verification**:
   - Confirm metrics appear in Grafana within 2-5 minutes
   - Check for "UP" status in Prometheus targets

### Troubleshooting

- **No Metrics**: check Prometheus

  ```bash
  kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
  kubectl logs -n monitoring <prometheus-pod-name> -c prometheus
  ```

- **Dashboard Issues**: check metrics labels and dashboards
  - Verify Grafana DataSource points to correct Prometheus instance
  - Check for template variable mismatches

## Cleanup

To permanently delete the cluster and all associated resources:

1. First modify the termination policy to ensure all resources are cleaned up:

```bash
# Set termination policy to WipeOut (deletes all resources including PVCs)
kubectl patch cluster -n demo milvus-cluster \
  -p '{"spec":{"terminationPolicy":"WipeOut"}}' \
  --type="merge"
```

2. Verify the termination policy was updated:

```bash
kubectl get cluster -n demo milvus-cluster -o jsonpath='{.spec.terminationPolicy}'
```

3. Delete the cluster:

```bash
kubectl delete cluster -n demo milvus-cluster
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

### Connecting to Milvus

To connect to the Milvus cluster, you can:

- port forward the Milvus service to your local machine:

```bash
kubectl port-forward svc/milvus-cluster-proxy -n demo 19530:19530
```

- or expose the Milvus service to the internet, as mentioned in the [Networking](#networking) section.

### Create Milvus Cluster with external Pulsar Cluster

There are cases a Pulsar/Minio/ETCD cluster has been provisioned in your environment, but not managed by KubeBlocks. To create a milvus cluster to use such "external-to-kubeblocks" cluster, you should use `serviceDescriptor` API instead `clusterServiceSelector`.

1. create `ServiceDescriptor`s.

ServiceDescriptor describes a service provided by external sources. It contains the necessary details such as the service's address and connection credentials.

For examples, create a ServiceDescriptor for etcd.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ServiceDescriptor
metadata:
spec:
  serviceKind: etcd
  serviceVersion: <etcd-version>
  endpoint:
    # external service endpoints here
    value: "<ETCD_ENDPOINT>"
  # Represents the port of the service connection credential.
  port:
    value: "2379"
```

2. create Milvus cluster, using `serviceRefs.serviceDescriptor` to point to an external service.

```yaml
  - name: querynode
    serviceRefs:
      - name: milvus-meta-storage
        namespace: demo
        # Specifies the name of the ServiceDescriptor object that describes a service provided by external sources
        serviceDescriptor: <ETCD_SD_NAME> # etcd servicd descriptor name created in step 1.
  ...
```

### List of K8s Resources created when creating an Milvus Cluster

To get the full list of associated resources created by KubeBlocks for given cluster:

```bash
kubectl get cmp,its,po -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # cluster and worload
kubectl get backuppolicy,backupschedule,backup -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # data protection resources
kubectl get componentparameter,parameter -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # configuration resources
kubectl get opsrequest -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # opsrequest resources
kubectl get svc,secret,cm,pvc -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # k8s native resources
```

## References
