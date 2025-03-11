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

### [Create](cluster.yaml)

Create a Loki cluster with four components, and saves data to local disk instead of remote object storage.
Please refer to [Loki Storage](https://grafana.com/docs/loki/latest/configure/storage/) for more detail on Chunk Storage.

- gateway : it is an Nginx Ingress pod that routes requests to the correct Loki components.
- read : read target
- write: write target
- backend: backend

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

#### [Scale-out](scale-out.yaml)

Horizontal scaling out by adding ONE more replica:

```bash
kubectl apply -f examples/loki/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling out by deleting ONE replica:

```bash
kubectl apply -f examples/loki/scale-in.yaml
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/loki/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/loki/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/loki/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/loki/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/loki/start.yaml
```

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Step 1. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

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
