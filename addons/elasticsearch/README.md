# Elasticsearch on KubeBlocks

## Overview

Elasticsearch is a distributed, RESTful search engine optimized for speed and relevance on production-scale workloads. Each Elasticsearch cluster consists of one or more nodes, with each node assuming specific roles.

### Node Roles

| Role | Description |
|------|-------------|
| **master** | Manages cluster state and coordinates operations |
| **data** | Stores data and handles data-related operations |
| **data_content** | Stores document data |
| **data_hot** | Handles recent, frequently accessed data |
| **data_warm** | Stores less frequently accessed data |
| **data_cold** | Handles rarely accessed data |
| **data_frozen** | Manages archived data |
| **ingest** | Processes documents before indexing |
| **ml** | Runs machine learning jobs |
| **remote_cluster_client** | Connects to remote clusters |
| **transform** | Handles data transformations |

[See Elasticsearch Node Roles documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html)

## Features in KubeBlocks

KubeBlocks provides comprehensive management capabilities for Elasticsearch clusters:

### Cluster Management Operations

| Operation |Supported | Description |
|-----------|-------------|----------------------|
| **Restart** | YES | • Ordered sequence (followers first)<br/>• Health checks between restarts |
| **Stop/Start** | YES |  • Graceful shutdown<br/>• Fast startup from persisted state |
| **Horizontal Scaling** |YES |  • Adjust replica count dynamically<br/>• Automatic data replication<br/> |
| **Vertical Scaling** | YES |  • Adjust CPU/Memory resources<br/>• Rolling updates for minimal downtime<br/>• Adaptive Parameters Reconfiguration, such as buffer pool size/max connections |
| **Volume Expansion** | YES |  • Online storage expansion<br/>• No downtime required |
| **Reconfiguration** | NO | • Dynamic/Static parameter updates<br/>• Validation rules<br/>• Versioned history |
| **Service Exposure** | YES |  • Multiple exposure types (ClusterIP/NodePort/LB)<br/>• Role-based routing |
| **Switchover** | N/A |  • Planned primary transfer<br/>• Zero data loss guarantee |

### Data Protection

| Type       | Method     | Details |
|---------------|------------|---------|
| N/A | N/A | N/A|

### Supported Versions

| Major Versions | Minor Versions|
|---------------|--------------|
| 7.x | 7.7.1,7.8.1,7.10.1 |
| 8.x | 8.1.3, 8.8.2 |

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes Environment**:
   - Cluster v1.21+
   - `kubectl` installed ([Installation Guide](https://kubernetes.io/docs/tasks/tools/))
   - Helm v3+ ([Installation Guide](https://helm.sh/docs/intro/install/))

2. **KubeBlocks Setup**:
   - KubeBlocks installed and running ([Installation](../docs/prerequisites.md))
   - Elasticsearch Addon enabled ([Addon Setup](../docs/install-addon.md))

3. **Namespace Setup**:
   Create an isolated namespace for this tutorial:

  ```bash
  kubectl create ns demo
  ```

## Lifecycle Management Operations

### Cluster Provisioning

#### Single-Node Cluster (Development/Testing)

For development and testing purposes, you can deploy a single-node cluster where one node handles all roles.

**Deployment Command:**

```yaml
# cat examples/elasticsearch/cluster-single-node.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: es-singlenode
  namespace: demo
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: mdit
      componentDef: elasticsearch-8
      serviceVersion: 8.8.2
      replicas: 1
      configs:
        - name: es-cm
          variables:
            mode: "single-node"
      resources:
        limits:
          cpu: "1"
          memory: "2Gi"
        requests:
          cpu: "1"
          memory: "2Gi"
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
kubectl apply -f examples/elasticsearch/cluster-single-node.yaml
```

**Configuration Details:**

```yaml
configs:
  - name: es-cm
    variables:
      mode: "single-node"  # Explicitly sets single-node mode
```

Key Configuration Notes:

- `es-cm`: References the config template in ComponentDefinition `elasticsearch-`
- `mode="single-node"`: Overrides default multi-node behavior

To check the role of the node, you may log in to the pod and run the following command:

```bash
curl -X GET "http://localhost:9200/_cat/nodes?v&h=name,ip,role"
```

And the expected output is as follows:

```text
name                  ip           role
es-single-node-mdit-0 12.345.678 cdfhilmrstw
```

The role is `cdfhilmrstw`. Please refer to [Elasticsearch Nodes](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html) for more information about the roles.

#### Multi-Node Cluster (Production)

For production deployments, create a cluster with dedicated nodes for different roles.

**Deployment Command:**

```yaml
# cat examples/elasticsearch/cluster-multi-node.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: es-multinode
  namespace: demo
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: data
      componentDef: elasticsearch-8
      serviceVersion: 8.8.2
      configs:
        - name: es-cm
          variables:
            # use key `roles` to specify roles this component assume
            roles: data,ingest,transform
      replicas: 3
      disableExporter: false
      resources:
        limits:
          cpu: "1"
          memory: "2Gi"
        requests:
          cpu: "1"
          memory: "2Gi"
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
    - name: master
      componentDef: elasticsearch-8
      serviceVersion: 8.8.2
      configs:
        - name: es-cm
          variables:
            # use key `roles` to specify roles this component assume
            roles: master
      replicas: 3
      disableExporter: false
      resources:
        limits:
          cpu: "1"
          memory: "2Gi"
        requests:
          cpu: "1"
          memory: "2Gi"
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
kubectl apply -f examples/elasticsearch/cluster-multi-node.yaml
```

**Configuration Example:**

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: elasticsearch-cluster
spec:
  componentSpecs:
    - name: data
      configs:
        - name: es-cm
          variables:
            roles: data,ingest,transform  # Node handles data, ingest and transform roles
            mode: multi-node
      replicas: 3
    - name: master
      configs:
        - name: es-cm
          variables:
            roles: master  # Dedicated master node
            mode: multi-node
      replicas: 3
```

Key Configuration Notes:

- `es-cm`: References the config template in ComponentDefinition
- `mode="multi-node"`: Explicit cluster mode (default)
- `roles`: Comma-separated list of node responsibilities

> [!IMPORTANT]
>
> - Roles will take effect only when `mode` is set to `multi-node`, or the `mode` is not set.
> - there must be one and only one component containing role 'master'
> - the component for role `mater` must be named to `master`

If you want to create a cluster with more roles, you can add more components and specify the roles in the configs.

```yaml
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: master
      configs:
        - name: es-cm
          variables:
            # use key `roles` to specify roles this component assume
            roles: master
    - name: data
      configs:
        - name: es-cm
          variables:
            # use key `roles` to specify roles this component assume
            roles: data
    - name: ingest
      configs:
        - name: es-cm
          variables:
            # use key `roles` to specify roles this component assume
            roles: ingest
    - name: transform
      configs:
        - name: es-cm
          variables:
            # use key `roles` to specify roles this component assume
            roles: transform
...
```

#### Version-Specific Cluster

To deploy a specific Elasticsearch version, configure the `serviceVersion` field in your cluster specification.

**Configuration Example:**

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: master
      serviceVersion: "8.8.2"  # Explicit version specification
      # Additional configuration...
```

**Checking Available Versions:**

```bash
kubectl get cmpv elasticsearch
```

<details open>
<summary>Sample Version Output</summary>

```bash
NAME            VERSIONS                         STATUS      AGE
elasticsearch   8.8.2,8.1.3,7.10.1,7.8.1,7.7.1   Available   21d
```

</details>

**Version Selection Guidelines:**

1. Always specify exact versions (avoid ranges)
2. Check version compatibility with your applications
3. Production environments should use stable releases (avoid pre-release versions)

### Cluster Restart

Restart the cluster components with zero downtime:

```yaml
# cat examples/elasticsearch/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: elasticsearch-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: es-multinode
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.If not specified, ALL Components will be restarted.
    # - master
    # - data
    # - ingest
    # - transform
  - componentName: data

```

```bash
kubectl apply -f examples/elasticsearch/restart.yaml
```

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
# cat examples/elasticsearch/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: elasticsearch-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: es-multinode
  type: Stop

```

```bash
kubectl apply -f examples/elasticsearch/stop.yaml
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
    - name: data
      stop: true  # Set to true to stop the component
      replicas: 3
```

#### Starting the Cluster

Start the cluster from its stopped state:

**Start via OpsRequest**

```yaml
# cat examples/elasticsearch/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: elasticsearch-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: es-multinode
  type: Start

```

```bash
kubectl apply -f examples/elasticsearch/start.yaml
```

**Start via Cluster API**

Update the cluster spec directly:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: data
      stop: false  # Set to false to start the component or remove the field (default to false)
      replicas: 3
```

## Scaling Operations

### Horizontal Scaling

#### Scale Out Operation

Add a new replica to the cluster:

```yaml
# cat examples/elasticsearch/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: es-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: es-multinode
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - master
    # - data
    # - ingest
    # - transform
  - componentName: master
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/elasticsearch/scale-out.yaml
```

To Check detailed operation status

```bash
kubectl describe ops -n demo elasticsearch-scale-out
```

### Scale In Operation

#### Standard Scale In Operation

Remove a replica from the cluster:

```yaml
# cat examples/elasticsearch/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: es-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: es-multinode
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - master
    # - data
    # - ingest
    # - transform
  - componentName: master
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/elasticsearch/scale-in.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo elasticsearch-scale-in
```

#### Horizontal Scaling via Cluster API

Directly update replica count via Cluster API:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: data
      replicas: 2  # Adjust replicas for scaling in and out.
      offlineInstances:
```

### Vertical Scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:

- CPU cores/processing power
- Memory (RAM)

#### Vertical Scaling via OpsRequest API

Perform vertical scaling using a operation request:

```yaml
# cat examples/elasticsearch/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: elasticsearch-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: es-multinode
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
    # Specifies the name of the Component.
    # - master
    # - data
    # - ingest
    # - transform
  - componentName: master
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: '3Gi'
    limits:
      cpu: '1'
      memory: '3Gi'

```

```bash
kubectl apply -f examples/elasticsearch/verticalscale.yaml
```

#### Vertical Scaling via Cluster API

Directly modify cluster specifications for vertical scaling:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: data
      resources:
        requests:
          cpu: "1"       # CPU cores (e.g. "1", "500m")
          memory: "2Gi"  # Memory (e.g. "2Gi", "512Mi")
        limits:
          cpu: "2"       # Maximum CPU allocation
          memory: "4Gi"  # Maximum memory allocation
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
# cat examples/elasticsearch/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: elasticsearch-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: es-multinode
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
    # - master
    # - data
    # - ingest
    # - transform
  - componentName: data
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
      # A reference to the volumeClaimTemplate name from the cluster components.
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/elasticsearch/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=elasticsearch-cluster -n demo
```

#### Volume Expansion via Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: data
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
# cat examples/elasticsearch/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: es-expose-enable
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: es-multinode
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
    # - master
    # - data
    # - ingest
    # - transform
  - componentName: master
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
      ports:
      - name: es-http
        port: 9200
        protocol: TCP
        targetPort: es-http
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Enable
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Expose

```

```bash
kubectl apply -f examples/elasticsearch/expose-enable.yaml
```

- Disable Service

```yaml
# cat examples/elasticsearch/expose-disable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: es-expose-disable
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: es-multinode
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
    # - master
    # - data
    # - ingest
    # - transform
  - componentName: master
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      serviceType: LoadBalancer
      ports:
      - name: es-http
        port: 9200
        protocol: TCP
        targetPort: es-http
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Disable
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Expose

```

```bash
kubectl apply -f examples/elasticsearch/expose-disable.yaml
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
      componentSelector: master
      name: master-internet
      serviceName: master-internet
      spec:
        ports:
        - name: es-http
          nodePort: 32751
          port: 9200
          protocol: TCP
          targetPort: es-http
        type: LoadBalancer
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
kubectl -n demo exec -it pods/es-multinode-data-0 -- \
  curl -s http://127.0.0.1:9114/metrics | head -n 50
```

Perform the verification against all ES replicas to.

2. **Apply PodMonitor**:

```yaml
# cat examples/elasticsearch/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: es-cluster-pod-monitor
  namespace: demo
  labels:               # this is labels set in `prometheus.spec.podMonitorSelector`
    release: prometheus
spec:
  podMetricsEndpoints:
    - path: /metrics
      port: metrics
      scheme: http
  namespaceSelector:
    matchNames:
      - demo
  selector:
    matchLabels:
      app.kubernetes.io/instance: es-multinode
```

  ```bash
  kubectl apply -f examples/elasticsearch/pod-monitor.yaml
  ```

  It set up the PodMonitor to scrape the metrics (port `9114`) from the Elasticsearch cluster.

  ```yaml
  - path: /metrics
    port: metrics
    scheme: http
  ```

#### 2. Grafana Dashboard Setup

1. **Import Dashboard**:
   - URL: [Elasticsearch Dashboard](https://raw.githubusercontent.com/apecloud/kubeblocks-addons/refs/heads/main/addons/elasticsearch/dashboards/elasticsearch.json)

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
kubectl patch cluster -n demo elasticsearch-cluster \
  -p '{"spec":{"terminationPolicy":"WipeOut"}}' \
  --type="merge"
```

2. Verify the termination policy was updated:

```bash
kubectl get cluster -n demo elasticsearch-cluster -o jsonpath='{.spec.terminationPolicy}'
```

3. Delete the cluster:

```bash
kubectl delete cluster -n demo elasticsearch-cluster
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

### Connecting to Elasticsearch

To connect to the Elasticsearch cluster, you can:

- port forward the Elasticsearch service to your local machine:

```bash
kubectl port-forward svc/es-multinode-master-http 9200:9200 -n demo
```

- or expose the Elasticsearch service to the internet, as mentioned in the [Networking](#networking) section.

Then you may use tools, such as kibana, elasticvue, as Web UI to interact with ES.

### List of K8s Resources created when creating an Elasticsearch Cluster

To get the full list of associated resources created by KubeBlocks for given cluster:

```bash
kubectl get cmp,its,po -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # cluster and worload
kubectl get backuppolicy,backupschedule,backup -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # data protection resources
kubectl get componentparameter,parameter -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # configuration resources
kubectl get opsrequest -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # opsrequest resources
kubectl get svc,secret,cm,pvc -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # k8s native resources
```

## References
