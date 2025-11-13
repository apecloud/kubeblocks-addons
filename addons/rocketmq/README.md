# RocketMQ

Apache RocketMQ is a distributed messaging and streaming platform with low latency, high performance and reliability, trillion-level capacity and flexible scalability.

## Features In KubeBlocks

### Lifecycle Management

|   Topology       | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| cluster          | Yes                    | Yes                   | Yes               | Yes       | Yes        | Yes       | Yes    | N/A        |

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

### Create

Create a rocketmq cluster::

```yaml
# cat examples/rocketmq/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  # The name of the RocketMQ cluster instance
  name: rocketmq-cluster
  # The namespace where the cluster will be deployed
  namespace: demo
spec:
  # Reference to the cluster definition that defines the cluster's behavior
  clusterDef: rocketmq
  # Specifies cluster topology defined in ClusterDefinition.Spec.topologies.
  # - `master-slave`
  topology: master-slave
  # Specifies the behavior when a Cluster is deleted.
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Component specifications - defines individual components of the cluster
  componentSpecs:
    # NameServer component - provides routing information for message producers and consumers
    - name: namesrv
      # Number of NameServer instances
      replicas: 1
      # Version of the RocketMQ NameServer
      serviceVersion: 4.9.6
      resources:
        limits:
          cpu: "2"
          memory: "2Gi"
        requests:
          cpu: "1"
          memory: "1Gi"
    # Exporter component - exposes metrics for monitoring
    - name: exporter
      replicas: 1
      # Version of the RocketMQ exporter
      serviceVersion: 0.0.3
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
        requests:
          cpu: "0.1"
          memory: "1Gi"
    # Dashboard component - provides web UI for cluster management
    - name: dashboard
      replicas: 1
      # Version of the RocketMQ dashboard
      serviceVersion: 2.0.1
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
        requests:
          cpu: "0.1"
          memory: "1Gi"
  # Shardings - defines horizontally sharded components (like brokers)
  shardings:
    - name: broker
      # Number of broker shards - each shard can have multiple replicas
      shards: 1
      template:
        # Template name for the broker instances
        name: rocketmq-broker
        # Number of replicas per shard (1 = master only, >1 = master with slaves)
        replicas: 2
        # Version of the RocketMQ broker
        serviceVersion: 4.9.6
        resources:
          limits:
            cpu: "2"
            memory: "4Gi"
          requests:
            cpu: "1"
            memory: "1Gi"
        # Persistent volume configuration for broker data storage
        volumeClaimTemplates:
          - name: data
            spec:
              # Volume access mode - ReadWriteOnce means single node read-write access
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  # Storage size for each broker instance
                  storage: 20Gi
```

```bash
kubectl apply -f examples/rocketmq/cluster.yaml
```

This creates a RocketMQ cluster with four components: nameserver, broker (with sharding), exporter, and dashboard.

### Horizontal scaling

Horizontal scaling for RocketMQ involves scaling the broker shards and nameserver replicas.

#### Scale-out NameServer by OpsRequest

Horizontal scaling out NameServer by adding ONE more replica:

```yaml
# cat examples/rocketmq/scale-out-namesrv.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rocketmq-name-server-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rocketmq-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: namesrv
    # Specifies the replica changes for scaling out components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/rocketmq/scale-out-namesrv.yaml
```

#### Scale-in NameServer by OpsRequest

Horizontal scaling in cluster by deleting ONE replica:

```yaml
# cat examples/rocketmq/scale-in-namesrv.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rocketmq-name-server-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rocketmq-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: namesrv
    # Specifies the replica changes for scaling out components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/rocketmq/scale-in-namesrv.yaml
```

On scale-in, the replica with the highest number (if not specified in particular) will be stopped and removed from the cluster.


#### Scale Broker Shards by OpsRequest

Horizontal scaling out Broker shards by adding ONE more shard:

```yaml
# cat examples/rocketmq/scale-shard-broker.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rocketmq-scale-shard
  namespace: demo
spec:
  clusterName: rocketmq-cluster
  type: HorizontalScaling
  horizontalScaling:
  - componentName: broker
    shard: 3
```

```bash
kubectl apply -f examples/rocketmq/scale-shard-broker.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` and `shards` field in cluster CR to your desired non-zero number.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: namesrv
      replicas: 3 # Update `replicas` to your desired number
  shardings:
    - name: broker
      shards: 3 # Update broker shards to your desired number
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/rocketmq/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rocketmq-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rocketmq-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: namesrv
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

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

### Expand volume

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

To increase size of volume storage with the specified components in the cluster

Increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/rocketmq/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rocketmq-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rocketmq-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: namesrv
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

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

### Restart

Restart the specified components in the cluster:

```yaml
# cat examples/rocketmq/restart-namesrv.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rocketmq-restart-namesrv
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rocketmq-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: namesrv

```

```bash
kubectl apply -f examples/rocketmq/restart-namesrv.yaml
```

### Expose

#### Expose NameServer by OpsRequest

```yaml
# cat examples/rocketmq/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rocketmq-expose-enable
  namespace: demo
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rocketmq-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: namesrv
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      # Determines how the Service is exposed. Defaults to 'ClusterIP'.
      # Valid options are `ClusterIP`, `NodePort`, and `LoadBalancer`.
      serviceType: LoadBalancer
      ports:
        - name: nameserver
          port: 9876
          targetPort: nameserver
      # Contains cloud provider related parameters if ServiceType is LoadBalancer.
      # [NOTE] Following is an example for Aliyun ACK, please adjust the following annotations as needed.
      annotations:
        service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: internet
        service.beta.kubernetes.io/alibaba-cloud-loadbalancer-charge-type: ""
        service.beta.kubernetes.io/alibaba-cloud-loadbalancer-spec: slb.s1.small
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Enable
```

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

### Reconfigure

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```yaml
# cat examples/rocketmq/reconfigure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rocketmq-reconfiguring
  namespace: demo
spec:
  # Specifies the type of this operation.
  type: Reconfiguring
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rocketmq-cluster
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: broker
    parameters:
      # Represents the name of the parameter that is to be updated.
      # `channel_max` is a static parameter in rocketmq
    - key: enableMultiDispatch
      # Represents the parameter values that are to be updated.
      # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
      value: "true"
```

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

```yaml
# cat examples/rocketmq/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: rocketmq-cluster-pod-monitor
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
      port: metrics
      scheme: http
  namespaceSelector:
    matchNames:
      - demo
  selector:
    matchLabels:
      app.kubernetes.io/instance: rocketmq-cluster
```

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

