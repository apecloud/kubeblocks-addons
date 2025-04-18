# Milvus

Milvus is an open source (Apache-2.0 licensed) vector database built to power embedding similarity search and AI applications. Milvus's architecture is designed to handle large-scale vector datasets and includes various deployment modes:  Milvus Standalone, and Milvus Distributed, to accommodate different data scale needs.

- Standalone Mode, including three components:
  - Milvus: Provides the core functionality of the system.
  - Metadata Storage (ETCD): A metadata engine for accessing and storing metadata of Milvus internal components (including proxies, index nodes, etc.), typically using etcd.
  - Object Storage (minio): A storage engine responsible for the persistence of Milvus data, typically using MinIO or S3-compatible storage services.

- Cluster Mode, including multiple layers:
  - Access Layer: composed of a group of stateless proxies
  - Worker Nodes:
    - Query Nodes
    - Data Nodes
    - Index Nodes
  - Coordinator Service: Manages the metadata of the cluster, including Root, Query , Data, and Index Coordinators.
  - Storage Layer, including
    - Metadata Storage (ETCD): A metadata engine for accessing and storing metadata of Milvus internal components, typically using etcd.
    - Object Storage (minio): A storage engine responsible for the persistence of Milvus data, typically using MinIO or S3-compatible storage services.
    - Log Storage (Pulsar): A log storage engine responsible for the persistence of Milvus logs, typically using Apache Pulsar.

## Features In KubeBlocks

### Lifecycle Management

| Topology | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|----------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Standalone/Cluster | Yes          | Yes                   | N/A           | Yes       | Yes        | N/A       | Yes    | N/A   |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| N/A | N/A | N/A |

### Versions

| Versions |
|----------|
| 2.3.2 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- **ETCD** , **Milvus** , **Pulsar** Addons Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

#### Standalone Mode

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

And then you can access the Milvus service via `localhost:19530`. For instance you can run the python code below to test the service:


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
      disableExporter: true
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

      disableExporter: true
    - name: datanode
      replicas: 1
      disableExporter: true
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
      disableExporter: true
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
      replicas: 1
      disableExporter: true
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

### Horizontal scaling

#### Scale-out

Horizontal scaling out `queryNode` in the cluster by adding ONE more replica:

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

#### Scale-in

Horizontal scaling in `queryNode` in the cluster by deleting ONE replica:

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

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: querynode
      replicas: 2 # Update `replicas` to 1 for scaling in, and to 3 for scaling out
```

### Restart

Restart the specified components in the cluster

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

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

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

### Start

Start the stopped cluster

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

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/milvus/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: milvus-cluster-pod-monitor
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
      - default
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

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo milvus-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo milvus-cluster
```
