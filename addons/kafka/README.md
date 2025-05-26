# Kafka on KubeBlocks

## Overview

Apache Kafka is a distributed streaming platform designed to build real-time pipelines and can be used as a message broker or as a replacement for a log aggregation solution for big data applications.

- A broker is a Kafka server that stores data and handles requests from producers and consumers. Kafka clusters consist of multiple brokers, each identified by a unique ID. Brokers work together to distribute and replicate data across the cluster.
- KRaft was introduced in Kafka 3.3.1 in October 2022 as an alternative to Zookeeper. A subset of brokers are designated as controllers, and these controllers provide the consensus services that used to be provided by Zookeeper.

## Features in KubeBlocks

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
| N/A | N/A | N/A |

### Supported Versions

| Versions |
|----------|
| 3.3.2 |
| 2.7.0 |

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes Environment**:
   - Cluster v1.21+
   - `kubectl` installed ([Installation Guide](https://kubernetes.io/docs/tasks/tools/))
   - Helm v3+ ([Installation Guide](https://helm.sh/docs/intro/install/))

2. **KubeBlocks Setup**:
   - KubeBlocks installed and running ([Installation](../docs/prerequisites.md))
   - Kafka Addon enabled ([Addon Setup](../docs/install-addon.md))

3. **Namespace Setup**:
   Create an isolated namespace for this tutorial:

  ```bash
  kubectl create ns demo
  ```

## Lifecycle Management Operations

### Cluster Provisioning

#### Quick Start

Create a Kafka cluster with controller, broker and a exporter components:

```yaml
# cat examples/kafka/cluster-separated.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: kafka-separated-cluster
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
  # The value must be `kafaka` to create a Kafka Cluster
  clusterDef: kafka
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  # - combined: combined Kafka controller (KRaft) and broker in one Component
  # - combined_monitor: combined mode with monitor component
  # - separated: separated KRaft and Broker Components.
  # - separated_monitor: separated mode with monitor component
  # Valid options are: [combined,combined_monitor,separated,separated_monitor]
  topology: separated_monitor
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: kafka-broker
      replicas: 3
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      env:
        - name: KB_KAFKA_BROKER_HEAP
          value: "-XshowSettings:vm -XX:MaxRAMPercentage=100 -Ddepth=64"
        - name: KB_KAFKA_CONTROLLER_HEAP
          value: "-XshowSettings:vm -XX:MaxRAMPercentage=100 -Ddepth=64"
        - name: KB_BROKER_DIRECT_POD_ACCESS
          value: "true"
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
        - name: metadata
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 1Gi
    - name: kafka-controller
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      volumeClaimTemplates:
        - name: metadata
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 1Gi
    - name: kafka-exporter
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: "1Gi"
        requests:
          cpu: "0.1"
          memory: "0.2Gi"
```

```bash
kubectl apply -f examples/kafka/cluster-separated.yaml
```

These three components will be created strictly in `controller->broker->exporter` order as defined in `ClusterDefinition`.

#### Create a `Combined` cluster

Create a Kafka cluster with combined controller and broker components

```yaml
# cat examples/kafka/cluster-combined.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: kafka-combined-cluster
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
  # The value must be `kafaka` to create a Kafka Cluster
  clusterDef: kafka
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  # - combined: combined Kafka controller (KRaft) and broker in one Component
  # - combined_monitor: combined mode with monitor component
  # - separated: separated KRaft and Broker Components.
  # - separated_monitor: separated mode with monitor component
  # Valid options are: [combined,combined_monitor,separated,separated_monitor]
  topology: combined_monitor
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: kafka-combine
      env:
        - name: KB_KAFKA_BROKER_HEAP # use this ENV to set BROKER HEAP
          value: "-XshowSettings:vm -XX:MaxRAMPercentage=100 -Ddepth=64"
        - name: KB_KAFKA_CONTROLLER_HEAP # use this ENV to set CONTOLLER_HEAP
          value: "-XshowSettings:vm -XX:MaxRAMPercentage=100 -Ddepth=64"
          # Whether to enable direct Pod IP address access mode.
          # - If set to 'true', Kafka clients will connect to Brokers using the Pod IP address directly.
          # - If set to 'false', Kafka clients will connect to Brokers using the Headless Service's FQDN.
        - name: KB_BROKER_DIRECT_POD_ACCESS
          value: "false"
      # Update `replicas` to your need.
      replicas: 1
      # Specifies the resources required by the Component.
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
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
                storage: 20Gi
        - name: metadata
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 1Gi
    - name: kafka-exporter # component for exporter
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: "1Gi"
        requests:
          cpu: "0.1"
          memory: "0.2Gi"
```

```bash
kubectl apply -f examples/kafka/cluster-combined.yaml
```

### Cluster Restart

Restart the cluster components with zero downtime:

```yaml
# cat examples/kafka/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-separated-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-separated-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: kafka-broker

```

```bash
kubectl apply -f examples/kafka/restart.yaml
```

This operation can only be performed via `OpsRequest`, and there is no corresponding CLUSTER API operation - because restart is not a declaration but an action. Replicas will be restarted one by one.

### Cluster Stop and Start

#### Stopping the Cluster

Gracefully stop the cluster to conserve resources while retaining all data (PVC). It is ideal for cost savings during inactive periods.

**Stop via OpsRequest**

```yaml
# cat examples/kafka/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name:  kafka-separated-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName:  kafka-separated-cluster
  type: Stop

```

```bash
kubectl apply -f examples/kafka/stop.yaml
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
    - name: kafka-broker
      stop: true  # Set to true to stop the component for all components
      replicas: 3
```

#### Starting the Cluster

Start the cluster from its stopped state:

**Start via OpsRequest**

```yaml
# cat examples/kafka/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-separated-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-separated-cluster
  type: Start

```

```bash
kubectl apply -f examples/kafka/start.yaml
```

**Start via Cluster API**

Update the cluster spec directly:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: kafka-brokder
      stop: false  # Set to false to start the component or remove the field (default to false) for all components
      replicas: 3
```

## Scaling Operations

### Horizontal Scaling

> [!IMPORTANT]
> As per the Kafka documentation, the number of KRaft replicas should be odd to avoid split-brain scenarios.
> Make sure the number of KRaft replicas, i.e. Controller replicas,  is always odd after Horizontal Scaling, either in Separated or Combined mode.

#### Scale Out Operation

Add a new replica to the cluster:

```yaml
# cat examples/kafka/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-separated-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-separated-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: kafka-broker
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/kafka/scale-out.yaml
```

To Check detailed operation status

```bash
kubectl describe ops -n demo kafka-scale-out
```

### Scale In Operation

#### Standard Scale In Operation

Remove a replica from the cluster:

```yaml
# cat examples/kafka/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-separated-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-separated-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: kafka-broker
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/kafka/scale-in.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo kafka-scale-in
```

#### Horizontal Scaling via Cluster API

Directly update replica count via Cluster API:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: kafka-broker
      replicas: 2  # Adjust replicas for scaling in and out.
      offlineInstances:
        - kafka-separated-cluster-kafka-broker-1 # for targetd-instance scale-in scenario, default to empty list.
```

### Vertical Scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:

- CPU cores/processing power
- Memory (RAM)

#### Vertical Scaling via OpsRequest API

Perform vertical scaling using a operation request:

```yaml
# cat examples/kafka/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-separated-vscale
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-separated-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: kafka-broker
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi
```

```bash
kubectl apply -f examples/kafka/verticalscale.yaml
```

#### Vertical Scaling via Cluster API

Directly modify cluster specifications for vertical scaling:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: kafka-broker
      resources:
        requests:
          cpu: "1"       # CPU cores (e.g. "1", "500m")
          memory: "2Gi"  # Memory (e.g. "2Gi", "512Mi")
        limits:
          cpu: "2"       # Maximum CPU allocation
          memory: "4Gi"  # Maximum memory allocation
```

**Key Considerations**:

- Ensure sufficient cluster capacity exists
- Resource changes may trigger pod restarts and parameters reconfiguration
- Monitor resource utilization after changes

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
# cat examples/kafka/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-separated-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-separated-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: kafka-broker
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/kafka/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=kafka-separated-cluster -n demo
```

#### Volume Expansion via Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: kafka-broker
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

1. **Get Exporter Details**:

  ```bash
  kubectl get po -n demo kafka-separated-cluster-kafka-broker-0 -oyaml | yq '.spec.containers[] | select(.name=="jmx-exporter") | .ports'
  ```

  <details open>
  <summary>Expected Output:</summary>

  ```text
  - containerPort: 5556
    name: metrics
    protocol: TCP
  ```

  </details>

  ```bash
   kubectl get po -n demo  kafka-separated-cluster-kafka-exporter-0 -oyaml | yq '.spec.containers[] | select(.name=="kafka-exporter") | .ports'
  ```

  <details open>
  <summary>Expected Output:</summary>

  ```text
  - containerPort: 9308
    name: metrics
    protocol: TCP
  ```

  </details>

2. **Verify Metrics Endpoint**:

   ```bash
   kubectl -n demo exec -it pods/kafka-separated-cluster-kafka-broker-0  -- \
     curl -s http://127.0.0.1:5556/metrics | head -n 50
   ```

3. **Apply PodMonitor**:

- Pod Monitor Kafka JVM:

```yaml
# cat examples/kafka/jvm-pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: kafka-pod-monitor
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
      app.kubernetes.io/instance: kafka-separated-cluster
```

```bash
kubectl apply -f examples/kafka/kafka-pod-monitor.yaml
```

#### 2. Grafana Dashboard Setup

1. **Import Dashboard**:
   KubeBlocks provides a Grafana dashboard for monitoring the Kafka cluster. You can find it at [Kafka Dashboard](https://github.com/apecloud/kubeblocks-addons/tree/main/addons/kafka/dashboards).
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
kubectl patch cluster -n demo kafka-separated-cluster \
  -p '{"spec":{"terminationPolicy":"WipeOut"}}' \
  --type="merge"
```

2. Verify the termination policy was updated:

```bash
kubectl get cluster -n demo kafka-separated-cluster -o jsonpath='{.spec.terminationPolicy}'
```

3. Delete the cluster:

```bash
kubectl delete cluster -n demo kafka-separated-cluster
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

### How to Access Kafka Cluster

#### With Direct Pod Access

To connect to the Kafka cluster, you can use the following command to get the service for connection:

```bash
kubectl get svc -l app.kubernetes.io/instance=<cluster-name> -n demo
```

And the excepted output is like below:

```text
NAME                                                         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kafka-combined-cluster-kafka-combine-advertised-listener-0   ClusterIP   10.96.221.254   <none>        9092/TCP   28m
```

You can connect to the Kafka cluster using the `CLUSTER-IP` and `PORT`.

##### With NodePort Service

Currently only `NodePort` and `ClusterIP` network modes are supported for Kafka.
To create Kafka cluster with `NodePort` services, you can create Kafka cluster with the following configuration. Please refer to [Kafka Network Modes Example](./cluster-combined-nodeport.yaml) for more details.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: kafka-combine
      services: # override default `advertised-listener` services, uset NodePort instead of ClusterIP
        - name: advertised-listener
          serviceType: NodePort
          podService: true
      replicas: 1
      env:
        - name: KB_KAFKA_BROKER_HEAP
          value: "-XshowSettings:vm -XX:MaxRAMPercentage=100 -Ddepth=64"
        - name: KB_KAFKA_CONTROLLER_HEAP
          value: "-XshowSettings:vm -XX:MaxRAMPercentage=100 -Ddepth=64"
        - name: KB_BROKER_DIRECT_POD_ACCESS # set KB_BROKER_DIRECT_POD_ACCESS to FALSE to disable direct pod access
          value: "false"
```

### Create Kafka Cluster with ServiceRef to Zookeeper

1. create a zookeeper cluster, either in KubeBlocks or not.
2. record zookeeper endpoints, e.g. `zookeeper-cluster-zookeeper-0.zookeeper-cluster-zookeeper-headless.demo:2181,zookeeper-cluster-zookeeper-1.zookeeper-cluster-zookeeper-headless.demo:2181,zookeeper-cluster-zookeeper-2.zookeeper-cluster-zookeeper-headless.demo:2181"`
3. edit 'examples/kafka/cluster-2x-ext-zk-svc-descriptor.yaml', replace zookeeper endpoints

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ServiceDescriptor
metadata:
spec:
  serviceKind: zookeeper
  serviceVersion: 3.8.5
  endpoint:
    # your external zk endpoints here
    value: "<ZOOKEEPER_ENDPOINTS>"
  # Represents the port of the service connection credential.
  port:
    value: "2181"
```

3. create kafka with external service reference to zookeeper.

```bash
kubectl create -f xamples/kafka/cluster-2x-ext-zk-svc-descriptor.yaml
```

### List of K8s Resources created when creating an Kafka Cluster

To get the full list of associated resources created by KubeBlocks for given cluster:

```bash
kubectl get cmp,its,po -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # cluster and worload
kubectl get backuppolicy,backupschedule,backup -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # data protection resources
kubectl get componentparameter,parameter -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # configuration resources
kubectl get opsrequest -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # opsrequest resources
kubectl get svc,secret,cm,pvc -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # k8s native resources
```

## References
