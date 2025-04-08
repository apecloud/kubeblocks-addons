# Loki

Loki is a horizontally-scalable, highly-available, multi-tenant log aggregation system inspired by Prometheus. It is designed to be very cost-effective and easy to operate, as it does not index the contents of the logs, but rather a set of labels for each log stream.

Loki decouples the data it stores from the software which ingests and queries it, and it provides differents mode up to your needs, with minimal or no configuration changes[^1].

- Monolithic mode: the simplest mode. It runs all Loki microservice components insider a single process.
- **Simple Scalable Mode**: the balanced mode. It separates execution paths into read, write, and backend targets.
- Microservices mode: runs components of Loki as distinct processes.

KubeBlocks provids the **Simple Scalable Mode** Loki Cluster, and there are tree execution pathes in this mode:

- the write target, stateful, and it contains the following components:
  - Distributor
  - Ingester
- the read target, stateless, and it contains the following components:
  - Query Frontend
  - Querier
- the backend target, stateful, and it contains the following components:
  - Compactor
  - Index Gateway
  - Query Scheduler
  - Ruler
  - Bloom Planner (experimental)
  - Bloom Builder (experimental)
  - Bloom Gateway (experimental)

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | Yes               | Yes       | Yes        | No        | Yes    | N/A   |

### Versions

| Versions |
|----------|
| v2.9.4   |

## Examples

### Create

Create a Loki cluster with four components, and saves data to local disk instead of remote object storage.
Please refer to [Loki Storage](https://grafana.com/docs/loki/latest/configure/storage/) for more detail on Chunk Storage.

- gateway : it is an Nginx Ingress pod that routes requests to the correct Loki components.
- read : read target
- write: write target
- backend: backend

```yaml
# cat examples/loki/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: lokicluster
  namespace: default
spec:
  terminationPolicy: Delete
  clusterDef: loki
  topology: loki-cluster
  services:
    - name: default
      serviceName: memberlist
      spec:
        ports:
          - name: tcp
            port: 7946
            targetPort: http-memberlist
            protocol: TCP
        selector:
          app.kubernetes.io/instance: lokicluster
          app.kubernetes.io/part-of: memberlist
  componentSpecs:
    - name: backend
      configs:
        - name: loki-config
          externalManaged: true
        - name: loki-runtime-config
          externalManaged: true
      disableExporter: true
      env:
        - name: STORAGE_TYPE
          value: "local"
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
            storageClassName: standard
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
    - name: write
      configs:
        - name: loki-config
          externalManaged: true
        - name: loki-runtime-config
          externalManaged: true
      disableExporter: true
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      env:
        - name: STORAGE_TYPE
          value: "local"
    - name: read
      configs:
        - name: loki-config
          externalManaged: true
        - name: loki-runtime-config
          externalManaged: true
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      disableExporter: true
      replicas: 1
      env:
        - name: STORAGE_TYPE
          value: "local"
    - name: gateway
      configs:
        - name: config-gateway
          externalManaged: true
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      disableExporter: true
      replicas: 1
```

```bash
kubectl apply -f examples/loki/cluster.yaml
```

> [!IMPORTANT]
> To use Loki in production environment, please config `replication_factor` to 3 (default to 1)
> The replication factor in Loki determines how many copies of log data are maintained across the cluster. This setting is crucial for ensuring data durability and high availability.

Choose an Appropriate Value:

- For **Production** Environments: Set the replication factor to **3**to ensure high availability and data durability. This means log data will be replicated across three different nodes.
- For **Development** or Testing: A replication factor of **1** is sufficient. This means no additional copies of the data will be made.

#### Add Loki as a new DataSource in Grafana

Go to `Grafana-> Connections -> Add New Data Source -> Loki` and set connection URL to `http://lokicluster-gateway.default.svc.cluster.local:80`.

### Horizontal scaling

#### Scale-out

Horizontal scaling out by adding ONE more replica:

```yaml
# cat examples/loki/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: loki-scale-out
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: loki-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - read
    # - write
    - componentName: write
      # Specifies the replica changes for scaling in components
      scaleOut:
        # Specifies the replica changes for the component.
        # add one more replica to current component
        replicaChanges: 1

```

```bash
kubectl apply -f examples/loki/scale-out.yaml
```

#### Scale-in

Horizontal scaling out by deleting ONE replica:

```yaml
# cat examples/loki/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: loki-scale-in
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: lokicluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - read
    # - write
    - componentName: write
      # Specifies the replica changes for scaling in components
      scaleIn:
        # Specifies the replica changes for the component.
        # add one more replica to current component
        replicaChanges: 1

```

```bash
kubectl apply -f examples/loki/scale-in.yaml
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/loki/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: loki-vscale
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: lokicluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
    # Specifies the name of the Component.
    # - backend
    # - write
    # - read
    - componentName: gateway
      # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
      requests:
        cpu: "1"
        memory: 1Gi
      limits:
        cpu: "1"
        memory: 1Gi

```

```bash
kubectl apply -f examples/loki/verticalscale.yaml
```

### Expand volume

Increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/loki/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: loki-volumeexpansion
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: lokicluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: backend
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/loki/volumeexpand.yaml
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/loki/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: loki-restart-vminsert
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: lokicluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
    # - backend
    # - write
    # - read
    - componentName: gateway

```

```bash
kubectl apply -f examples/loki/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/loki/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: loki-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: lokicluster
  type: Stop

```

```bash
kubectl apply -f examples/loki/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/loki/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: loki-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: lokicluster
  type: Start

```

```bash
kubectl apply -f examples/loki/start.yaml
```

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Step 1. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/loki/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: loki-cluster-pod-monitor
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
      - default
  selector:
    matchLabels:
      app.kubernetes.io/instance: lokicluster
```

```bash
kubectl apply -f examples/loki/pod-monitor.yaml
```

##### Step 2. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard , e.g.

- Loki Metrics Dashboard: <https://github.com/frank-fegert/grafana-dashboards/blob/main/Loki_Metrics_Dashboard.json>

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster vmcluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster vmcluster
```

## References

[^1]: Loki Deployment Mode, <https://grafana.com/docs/loki/latest/get-started/deployment-modes/#simple-scalable>
