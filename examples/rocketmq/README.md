# RocketMQ

Apache RocketMQ is a distributed messaging and streaming platform with low latency, high performance and reliability, trillion-level capacity and flexible scalability.

## Features In KubeBlocks

### Lifecycle Management

|   Topology       | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| cluster          | Yes (NameServer)       | Yes                   | Yes               | Yes       | Yes        | Yes       | Yes    | N/A        |

### Versions

| Major Versions | Description |
|---------------|-------------|
| 4.x | 4.9.6 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- RocketMQ Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

Create a rocketmq cluster::

```bash
kubectl apply -f examples/rocketmq/cluster.yaml
```

This creates a RocketMQ cluster with four components: nameserver, broker (with sharding), exporter, and dashboard.

### Horizontal scaling

Horizontal scaling for RocketMQ involves scaling the broker shards and nameserver replicas.

#### Scale-out NameServer by OpsRequest

Horizontal scaling out NameServer by adding ONE more replica:

```bash
kubectl apply -f examples/rocketmq/scale-out-namesrv.yaml
```

#### Scale-in NameServer by OpsRequest

Horizontal scaling in cluster by deleting ONE replica:

```bash
kubectl apply -f examples/rocketmq/scale-in-namesrv.yaml
```

On scale-in, the replica with the highest number (if not specified in particular) will be stopped and removed from the cluster.

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` and `shards` field in cluster CR to your desired non-zero number.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: namesrv
      replicas: 3 # Update `replicas` to your desired number
```

> [!NOTE]
> Horizontal scaling of Broker is not fully supported yet.

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/rocketmq/verticalscale.yaml
```

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: namesrv
      resources:
        requests:
          cpu: "1"       # Update the resources to your need.
          memory: "2Gi"  # Update the resources to your need.
        limits:
          cpu: "2"       # Update the resources to your need.
          memory: "4Gi"  # Update the resources to your need.
```

### [Expand volume](volumeexpand.yaml)

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

To increase size of volume storage with the specified components in the cluster

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/rocketmq/volumeexpand.yaml
```

#### Volume expansion using Cluster API

Alternatively, you may update the `volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  shardings:
    - name: broker
      shards: 3
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                # specify new size, and make sure it is larger than the current size
                storage: 30Gi
```

### [Restart](restart.yaml)

Restart the specified components in the cluster:

```bash
kubectl apply -f examples/rocketmq/restart-namesrv.yaml
```

### Expose

#### Expose NameServer by OpsRequest

```bash
kubectl apply -f examples/rocketmq/expose-enable.yaml
```

#### Expose SVC using Cluster API

Alternatively, you may expose service by updating `spec.services`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  services:
  - annotations:
      # aws annotations
      service.beta.kubernetes.io/aws-load-balancer-type: nlb  # Use Network Load Balancer
      service.beta.kubernetes.io/aws-load-balancer-internal: "true"  # or "false" for internet
    componentSelector: namesrv
    name: rocketmq-namesrv
    serviceName: rocketmq-namesrv
    spec:
      ports:
      - name: nameserver
        port: 9876
        protocol: TCP
        targetPort: nameserver
      type: LoadBalancer
```

If the service is of type `LoadBalancer`, please add annotations for cloud loadbalancer depending on the cloud provider you are using. Here list annotations for some cloud providers:

| Cloud Provider | Annotation Key | Value | Description |
|----------------|----------------|-------|-------------|
| Alibaba Cloud | `service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type` | `"internet"` or `"intranet"` | Specifies whether the load balancer is internet-facing or internal |
| AWS | `service.beta.kubernetes.io/aws-load-balancer-type` | `nlb` | Use Network Load Balancer |
| AWS | `service.beta.kubernetes.io/aws-load-balancer-internal` | `"true"` or `"false"` | `"true"` for internal, `"false"` for internet-facing |
| Azure | `service.beta.kubernetes.io/azure-load-balancer-internal` | `"true"` or `"false"` | `"true"` for internal, `"false"` for internet-facing |
| GCP | `networking.gke.io/load-balancer-type` | `"Internal"` | For internal access |
| GCP | `cloud.google.com/l4-rbs` | `"enabled"` | For internet-facing load balancer |

Please consult your cloud provider for more accurate and update-to-date information.

### [Reconfigure](reconfigure.yaml)

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```bash
kubectl apply -f examples/rocketmq/reconfigure.yaml
```

This example demonstrates how to reconfigure RocketMQ broker parameters dynamically.

To verify the change, you can login to any nameserver replica and run the following command:
```bash
# Get broker addresses
> ${ROCKETMQ_HOME}/bin/mqadmin clusterList -n 127.0.0.1:9876
# Get broker configuration for the broker addresses
> ${ROCKETMQ_HOME}/bin/mqadmin getBrokerConfig -n 127.0.0.1:9876 -b <broker-address>:<broker-port>
```


### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

##### Step 1. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```bash
kubectl apply -f examples/rocketmq/pod-monitor.yaml
```

It sets path to `/metrics` and port to `metrics` (for container port `5556` and `5557`).

```yaml
    - path: /metrics
      port: metrics
      scheme: http
```

After applying the `PodMonitor`, you should see the metrics in the Prometheus dashboard. It may take a few minutes for prometheus to reload and scrape the targets.

Once the target is available, you can check the metrics `up` through prometheus query.

```bash
curl -sG "http://<PROMETHEUS_SERVICE_NAME>:9090/api/v1/query" --data-urlencode 'query=up{app_kubernetes_io_instance="rocketmq-cluster"}' | jq
```

##### Step 2. Access the Grafana Dashboard

Login to the Grafana dashboard and create visualizations for RocketMQ metrics exposed by the exporter component.

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Then access the Grafana dashboard at `http://localhost:3000/`.

> [!NOTE]
> Make sure the labels are set correctly in the `PodMonitor` file to match your dashboard queries.


### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo rocketmq-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete -f examples/rocketmq/cluster.yaml
```

## Appendix

### How to access RocketMQ Management Console

To access the RocketMQ Management console , you can port-forward the dashboard service:

```bash
kubectl port-forward svc/rocketmq-cluster-dashboard 18080:8080
```

Then access the RocketMQ Management console at `http://localhost:18080/`.