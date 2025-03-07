# VictoriaMetrics

VictoriaMetrics is a fast, scalable, and resource-efficient open-source time-series database (TSDB) and monitoring solution. It is designed to handle high volumes of time-series data with high performance and low resource usage. VictoriaMetrics is compatible with Prometheus, Grafana, and other monitoring tools.

VictoriaMetrics can run in two modes:

1. **Single-Node**: All-in-one deployment for smaller workloads.
2. **Cluster Mode**: Distributed architecture for large-scale deployments.

## Core Components (Cluster Mode)

1. **vmstorage**
  Stateful, stores time-series data. Handles data partitioning and replication.
2. **vminsert**
  Stateless, Accepts ingested data and routes it to the appropriate `vmstorage` node.
3. **vmselect**
  Stateless, Handles queries by aggregating results from `vmstorage` nodes.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | Yes               | Yes       | Yes        | No        | Yes    | N/A   |

### Versions

| Versions |
|----------|
| v1.101.0 |

## Examples

### [Create](cluster.yaml)

Create a tdengine cluster:

```bash
kubectl apply -f examples/victoria-metrics/cluster.yaml
```

#### Set Prometheus remote write to VM

When the cluster status is `Running`, you may set Prometheus `remote_write` to VM by setting:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
spec:
...
 remoteWrite:
  # http://<vminsert-addr>:8480/insert/{tenantID}/prometheus
  - url: http://vmcluster-vminsert.default.svc.cluster.local:8480/insert/0/prometheus
...
```

#### Add VM as a new DataSource in Grafana

Go to `Grafana-> Connections -> Add New Data Source -> Prometheus` and set connection URL to `http://vmcluster-vmselect.default.svc.cluster.local:8481/select/0/prometheus`,
where `0` is tenant ID.

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out by adding ONE more replica:

```bash
kubectl apply -f examples/victoria-metrics/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling out by deleting ONE replica:

```bash
kubectl apply -f examples/victoria-metrics/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: vmselect
      replicas: 3 # Set the number of replicas to your desired number
```

#### Caution: Scale-in/out VMStorage

**Scaling Out** vmstorage

1. Scale-Out `vmstorage` by adding one more instance.
1. Restart `vmselect` component.
1. Restart `vminsert` component.

- Restart ONE or TWO replica first, and observe the time-series count metrics of the entire cluster.
- Wait for the cluster to stabilize, then upgrade and restart the remaining `vminsert` replicas.

**Scaling In** vmstorage
The scaling-down process is the reverse of scaling up. First, restart `vminsert`, then restart `vmselect`. If the new `vmstorage` instance is only in `vminsert` and not in `vmselect`, data written to the new `vmstorage` instance will be unqueryable until the new instance is added to `vmselect`.

> [!IMPORTANT] Why Gradual Restart is Necessary for `vminsert` Upgrades

When the `storageNode` list changes, some timeseries may be relocated. For example, a timeseries previously stored on `Node A` might be stored on `Node B` after the restart. If a large number of new timeseries suddenly appear on `Node B`, it can severely impact performance. Additionally, if the `-storage.maxHourlySeries` or `-storage.maxDailySeries` limits are reached, `BNode` may reject the newly migrated timeseries.

Therefore, we only upgrade one or two `vminsert` instances initially. This allows a small number of requests to shift, enabling the migrated timeseries to create indexes on the new Storage Node (index creation is resource-intensive). After this, we upgrade the remaining `vminsert` instances.

To achieve controlled `Gradual Restart` of vminsert, we use `instanceUpdateStrategy` API in KubeBlocks:

```yaml
    - name: vminsert
      # This configuration ensures that when updates are applied to the cluster,
      # only 1 replicas will be updated at a time.
      instanceUpdateStrategy:
        type: RollingUpdate
        rollingUpdate:
          maxUnavailable: 1
          replicas: 1
```

When the cluster goes stable, patch the cluster with set `replicas: 2` to update one more replicas, and set `replicas: <total_replicas>` to update all remaining replicas.

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/victoria-metrics/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/victoria-metrics/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/victoria-metrics/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/victoria-metrics/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/victoria-metrics/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster vmcluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster vmcluster
```

## References
