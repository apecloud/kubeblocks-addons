# StarRocks

StarRocks is a Linux Foundation project, it is the next-generation data platform designed to make data-intensive real-time analytics fast and easy.

StarRocks supports **shared-nothing** (Each BE has a portion of the data on its local storage) and **shared-data** (all data on object storage or HDFS and each CN has only cache on local storage).

- FrontEnds (FE) are responsible for metadata management, client connection management, query planning, and query scheduling. Each FE stores and maintains a complete copy of the metadata in its memory, which guarantees indiscriminate services among the FEs.
- BackEnds (BE) are responsible for data storage, data processing, and query execution. Each BE stores a portion of the data and processes the queries in parallel.

KubeBlocks supports creating a **shared-nothing** StarRocks cluster.

## Features In KubeBlocks

### Lifecycle Management

|   Topology       | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| shared-nothing     | Yes                  | Yes                   | Yes               | Yes       | Yes        | No        | Yes    | N/A      |

### Versions

| Major Versions | Description |
|----------------|-------------|
| 3.3.x          | 3.3.0, 3.3.2|

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- StarRocks-CE Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### [Create](cluster.yaml)

Create a StarRocks cluster with 3 FE and 2 BE instances. Backend instances won't be created until the FrontEnds instances are ready.
For high availability, it is recommended to have at least 3 FE instances.

```yaml
# cat examples/starrocks-ce/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: starrocks-cluster
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
  # The value must be `starrocks-ce` to create a StarRocks-CE Cluster
  clusterDef: starrocks-ce
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  # Valid options are: [shared-nothing]
  topology: shared-nothing
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: fe # for fronetent component
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [3.3.0,3.2.2]
      serviceVersion: 3.3.0
      # NOTE: Set `replicas` to 3 in production env.
      replicas: 3
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
        requests:
          cpu: "1"
          memory: "1Gi"
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
    - name: be # for backend component
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [3.3.0,3.2.2]
      serviceVersion: 3.3.0
      replicas: 2
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
        requests:
          cpu: "1"
          memory: "1Gi"
      # Specifies a list of PersistentVolumeClaim templates that define the storage
      # requirements for the Component.
      volumeClaimTemplates:
        # Refers to the name of a volumeMount defined in
        # `componentDefinition.spec.runtime.containers[*].volumeMounts
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
kubectl apply -f examples/starrocks-ce/cluster.yaml
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out component BE by adding ONE more replica:

```yaml
# cat examples/starrocks-ce/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: sr-scale-out
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: starrocks-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: be
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/starrocks-ce/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling out component BE by delete ONE more replica:

```yaml
# cat examples/starrocks-ce/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: sr-scale-in
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: starrocks-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: be
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/starrocks-ce/scale-in.yaml
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/starrocks-ce/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: starrocks-verticalscaling
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: starrocks-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: be
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1.5'
      memory: 1.5Gi
    limits:
      cpu: '1.5'
      memory: 1.5Gi

```

```bash
kubectl apply -f examples/starrocks-ce/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/starrocks-ce/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: starrocks-volumeexpansion
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: starrocks-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: be
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/starrocks-ce/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```yaml
# cat examples/starrocks-ce/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: starrocks-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: starrocks-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
    # - be
    # - fe
  - componentName: be

```

```bash
kubectl apply -f examples/starrocks-ce/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/starrocks-ce/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: starrocks-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: starrocks-cluster
  type: Stop

```

```bash
kubectl apply -f examples/starrocks-ce/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```yaml
# cat examples/starrocks-ce/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: starrocks-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: starrocks-cluster
  type: Start

```

```bash
kubectl apply -f examples/starrocks-ce/start.yaml
```

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/starrocks-ce/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: sr-cluster-pod-monitor
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
      port: http-port
      scheme: http
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_label_apps_kubeblocks_io_component_name]
          action: replace
          targetLabel: service
  namespaceSelector:
    matchNames:
      - default
  selector:
    matchLabels:
      app.kubernetes.io/instance: starrocks-cluster

```

```bash
kubectl apply -f examples/starrocks-ce/pod-monitor.yaml
```

It sets up the `PodMonitor` to monitor this StarRocks cluster and scrapes the metrics for both FE and BE components.

```yaml
  podMetricsEndpoints:
    - path: /metrics
      port: http-port
      scheme: http
      relabelings:
        # Add relabeling configuration to extract value from pod label
        # Use sourceLabels to specify the label to extract from
        # Use action: replace to set the value
        # Set targetLabel as "service"
        - sourceLabels: [__meta_kubernetes_pod_label_apps_kubeblocks_io_component_name]
          action: replace
          targetLabel: service
```

##### Access the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard provided in this example `./examples/starrocks-ce/dashboard/starrocks.json`.

You may refer to following links for more information:
- StarRocks Overview provided by StarRocks team: [StarRocks Overview](https://github.com/StarRocks/starrocks/blob/main/extra/grafana/kubernetes/StarRocks-Overview-kubernetes-3.0.json)
- [Monitor and Alert with Prometheus and Grafana](https://docs.starrocks.io/docs/administration/management/monitoring/Monitor_and_Alert/)

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster starrocks-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster starrocks-cluster
```
