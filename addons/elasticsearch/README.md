# Elasticsearch

Elasticsearch is a distributed, RESTful search engine optimized for speed and relevance on production-scale workloads.
Each Elasticsearch cluster consists of one or more nodes, and each node in a cluster has a role and communicates with other nodes to share data and responsibilities. A node can assume multiple roles up to your requirements. Types of roles include [^1]:

- master
- data
- data_content
- data_hot
- data_warm
- data_cold
- data_frozen
- ingest
- ml
- remote_cluster_client
- transform

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | Yes               | Yes       | Yes        | No       | Yes    | N/A     |

### Versions

| Major Versions | Description |
|---------------|-------------|
| 7.x | 7.7.1,7.8.1,7.10.1 |
| 8.x | 8.1.3, 8.8.2 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Elasticsearch Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

#### Create a Single-Node Cluster

A Single-Node Cluster is a cluster with only one node and this node assume all roles. It is suitable for development and testing purposes.

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

The configs in Cluster API:

```yaml
  configs:
    - name: es-cm
      variables:
        mode: "single-node"
```

Where,

- `es-cm` refers to the config template defined in ComponentDefinition `elasticsearch-`
- "mode=single-node" (default to multi-node), is used to specify the mode of the Elasticsearch cluster.

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

#### Create a Multi-Node Cluster

Create a elasticsearch cluster with multiple nodes and each node assume specified roles.

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

There are four components specified in this cluster, i.e 'master', 'data', 'ingest', and 'transform',  and each component has different roles. Roles are specified in `configs` for each component:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
spec:
  componentSpecs:
    - name: data
      configs:
        - name: es-cm
          variables:
            # use key `roles` to specify roles this component assume
            roles: data,ingest,transform
            mode: multi-node
      ...
    - name: master
      configs:
        - name: es-cm
          variables:
            # use key `roles` to specify roles this component assume
            roles: master
            mode: multi-node
```

Where,

- `es-cm` refers to the config template defined in ComponentDefinition `elasticsearch-`
- "mode=multi-node" (default to multi-node), is used to specify the mode of the Elasticsearch cluster.
- "roles: data,ingest,transform" specifies the list of roles this component should assume.

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

### Horizontal scaling

#### Scale-out

Horizontal scaling out elasticsearch cluster by adding ONE `MASTER` replica:

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

#### Scale-in

Horizontal scaling in elasticsearch cluster by deleting ONE `MASTER` replica:

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

On scaling in, the pod with the highest ordinal number (if not otherwise specified) will be deleted. And it will be cleared from voting configuration exclusions of this cluster before deletion, to make sure the cluster is healthy.

After scaling in, you can check the cluster health by running the following command:

```bash
curl -X GET "http://<ES_ENDPOINT>:9200/_cluster/health?pretty"  # replace <ES_ENDPOINT> with the actual endpoint
```

> [!IMPORTANT]
> Make sure there are at least ONE replica for each component
> If you want to scale in the last replica, may be you should consider to `STOP` the cluster.

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: master
      componentDef: elasticsearch-8
      serviceVersion: 8.8.2
      replicas: 3 # Update `replicas` to your need.
```

### Vertical scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

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

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: master
      componentDef: elasticsearch-8
      serviceVersion: 8.8.2
      resources:
        requests:
          cpu: "1"       # Update the resources to your need.
          memory: "2Gi"  # Update the resources to your need.
        limits:
          cpu: "2"       # Update the resources to your need.
          memory: "4Gi"  # Update the resources to your need.
```

### Expand volume

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created. It is introduced in Kubernetes v1.11 and goes GA in Kubernetes v1.24. It allows Kubernetes users to simply edit their PersistentVolumeClaim objects  without requiring any downtime at all if possible.

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

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

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: master
      componentDef: elasticsearch-8
      serviceVersion: 8.8.2
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: "<you-preferred-sc>"
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 30Gi  # specify new size, and make sure it is larger than the current size
```

### Restart

Restart the specified component `data` in the cluster. If not specified, all components will be restarted.

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

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

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

#### Stop using Cluster API

Alternatively, you may stop ONE component by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: master
      componentDef: elasticsearch-8
      serviceVersion: 8.8.2
      stop: true  # set stop `true` to stop the component
      replicas: 3
```

### Start

Start the stopped cluster

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

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: master
      componentDef: elasticsearch-8
      serviceVersion: 8.8.2
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 3
```

### Expose

It is recommended to access the Elasticsearch cluster from within the Kubernetes cluster using Kibana or other tools. However, if you need to access the Elasticsearch cluster from outside the Kubernetes cluster, you can expose the Elasticsearch service using a `LoadBalancer` service type.

#### Enable

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

In this example, a service with type `LoadBalancer` will be created to expose the Elasticsearch cluster. You can access the cluster using the `external IP` of the service.

#### Disable

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

#### Expose SVC using Cluster API

Alternatively, you may expose service by updating `spec.services`

```yaml
spec:
  # append service to the list
  services:
    # add annotation for cloud loadbalancer if
    # services.spec.type is LoadBalancer
    # here we use annotation for alibaba cloud for example
  - annotations:
      service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: internet
      service.beta.kubernetes.io/alibaba-cloud-loadbalancer-charge-type: ""
      service.beta.kubernetes.io/alibaba-cloud-loadbalancer-spec: slb.s1.small
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

If the service is of type `LoadBalancer`, please add annotations for cloud loadbalancer depending on the cloud provider you are using. Here list annotations for some cloud providers:

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

Please consult your cloud provider for more accurate and update-to-date information.

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

##### Step 1. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/elasticsearch/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: es-cluster-pod-monitor
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

##### Step 2. Access the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard.
You can import the dashboard provided by Grafana or create your own dashboard, e.g.

- <https://grafana.com/grafana/dashboards/2322-elasticsearch/>

> [!NOTE]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo es-multinode -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo es-multinode
```

## References

[^1]: Elasticsearch Nodes, <https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html>
