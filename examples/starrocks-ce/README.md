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

```bash
kubectl apply -f examples/starrocks-ce/cluster.yaml
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out component BE by adding ONE more replica:

```bash
kubectl apply -f examples/starrocks-ce/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling out component BE by delete ONE more replica:

```bash
kubectl apply -f examples/starrocks-ce/scale-in.yaml
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/starrocks-ce/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/starrocks-ce/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/starrocks-ce/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/starrocks-ce/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

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
