# Kafka

Apache Kafka is a distributed streaming platform designed to build real-time pipelines and can be used as a message broker or as a replacement for a log aggregation solution for big data applications.

- A broker is a Kafka server that stores data and handles requests from producers and consumers. Kafka clusters consist of multiple brokers, each identified by a unique ID. Brokers work together to distribute and replicate data across the cluster.
- KRaft was introduced in Kafka 3.3.1 in October 2022 as an alternative to Zookeeper. A subset of brokers are designated as controllers, and these controllers provide the consensus services that used to be provided by Zookeeper.

## Features In KubeBlocks

### Lifecycle Management

| Topology | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|----------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Combined/Separated | Yes          | Yes                   | Yes               | Yes       | Yes        | Yes       | Yes    | N/A   |

- Combine Mode: KRaft (Controller) and Broker components are combined in the same pod.
- Separated Mode: KRaft (Controller) and Broker components are deployed in different pods.

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| N/A | N/A | N/A |

### Versions

| Versions |
|----------|
| 3.3.2 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Kafka Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### Create

Create a Kafka cluster with combined controller and broker components

```yaml
# cat examples/kafka/cluster-combined.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: kafka-combined-cluster
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
      configs:
        - name: kafka-configuration-tpl
          externalManaged: true
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

Create a Kafka cluster with separated controller and broker components:

```yaml
# cat examples/kafka/cluster-separated.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: kafka-separated-cluster
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
      configs:
        - name: kafka-configuration-tpl
          externalManaged: true
      replicas: 1
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
      configs:
        - name: kafka-configuration-tpl
          externalManaged: true
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

### Horizontal scaling

> [!IMPORTANT]
> As per the Kafka documentation, the number of KRaft replicas should be odd to avoid split-brain scenarios.
> Make sure the number of KRaft replicas, i.e. Controller replicas,  is always odd after Horizontal Scaling, either in Separated or Combined mode.

#### Scale-out

Horizontal scaling out `kafka-combine` component in cluster `kafka-combined-cluster` by adding ONE more replica:

```yaml
# cat examples/kafka/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-combined-scale-out
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-combined-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: kafka-combine
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/kafka/scale-out.yaml
```

After applying the operation, you will see a new pod created. You can check the progress of the scaling operation with following command:

```bash
kubectl describe ops kafka-combined-scale-out
```

#### Scale-in

Horizontal scaling in  `kafka-combine` component in cluster `kafka-combined-cluster` by deleting ONE replica:

```yaml
# cat examples/kafka/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-combined-scale-in
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-combined-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: kafka-combine
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/kafka/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: kafka-combine
      replicas: 1 # Set the number of replicas to your desired number
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster:

```yaml
# cat examples/kafka/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-combined-vscale
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-combined-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: kafka-combine
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

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: kafka-combine
      replicas: 1
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

To increase size of volume storage with the specified components in the cluster:

```yaml
# cat examples/kafka/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-combined-volumeexpansion
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-combined-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: kafka-combine
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
kubectl get pvc -l app.kubernetes.io/instance=kafka-combined-cluster -n default
```

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: kafka-combine
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: "<you-preferred-sc>"
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 30Gi  # specify new size, and make sure it is larger than the current size
        - name: metadata
          spec:
            storageClassName: "<you-preferred-sc>"
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 10Gi  # specify new size, and make sure it is larger than the current size
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/kafka/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-combine-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-combined-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: kafka-combine

```

```bash
kubectl apply -f examples/kafka/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/kafka/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name:  kafka-combine-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName:  kafka-combined-cluster
  type: Stop

```

```bash
kubectl apply -f examples/kafka/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: kafka-combine
      stop: true  # set stop `true` to stop the component
      replicas: 1
```

### Start

Start the stopped cluster

```yaml
# cat examples/kafka/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: kafka-combined-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-combined-cluster
  type: Start

```

```bash
kubectl apply -f examples/kafka/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: kafka-combine
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 1
```

### Reconfigure

Configure parameters with the specified components in the cluster

```yaml
# cat examples/kafka/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name:  kafka-combined-reconfiguring
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: kafka-combined-cluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: kafka-combine
   # Contains a list of ConfigurationItem objects, specifying the Component's configuration template name, upgrade policy, and parameter key-value pairs to be updated.
    parameters:
      # Represents the name of the parameter that is to be updated.
    - key: log.flush.interval.ms
      # Represents the parameter values that are to be updated.
      # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
      value: "2000"
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring

```

```bash
kubectl apply -f examples/kafka/configure.yaml
```

This example update `log.flush.interval.ms` parameter of the `kafka-combine` component in the cluster `kafka-combined-cluster` to `1000`.
This parameter is the maximum time in ms that a message in any topic is kept in memory before flushed to disk. If not set, the value in log.flush.scheduler.interval.ms is used.

To verify the configuration change, you may log into the pod and check the configuration file.

```bash
cat  /opt/bitnami/kafka/config/kraft/server.properties | grep 'log.flush.interval.ms'
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster kafka-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster kafka-cluster
```

### Observability

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create Cluster

Create a Kafka cluster with separated controller and broker components for instance:

```yaml
# cat examples/kafka/cluster-separated.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: kafka-separated-cluster
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
      configs:
        - name: kafka-configuration-tpl
          externalManaged: true
      replicas: 1
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
      configs:
        - name: kafka-configuration-tpl
          externalManaged: true
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

#### Create PodMonitor

##### Step 1. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster.
Please set the labels correctly in the `PodMonitor` file to match the target pods.

```yaml
# cat pod monitor file
  selector:
    matchLabels:
      app.kubernetes.io/instance: kafka-separated-cluster  # cluster name, set it to your cluster name
      apps.kubeblocks.io/component-name: kafka-controller  # component name
```

- Pod Monitor Kafka JVM:

```yaml
# cat examples/kafka/jvm-pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: kafka-jmx-pod-monitor
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
      - default
  selector:
    matchLabels:
      app.kubernetes.io/instance: kafka-separated-cluster
      apps.kubeblocks.io/component-name: kafka-controller
```

```bash
kubectl apply -f examples/kafka/jvm-pod-monitor.yaml
```

- Pod Monitor for Kafka Exporter:

```yaml
# cat examples/kafka/exporter-pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: kafka-exporter-pod-monitor
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
      - default
  selector:
    matchLabels:
      app.kubernetes.io/instance: kafka-separated-cluster
      apps.kubeblocks.io/component-name: kafka-exporter
```

```bash
kubectl apply -f examples/kafka/exporter-pod-monitor.yaml
```

##### Step 2. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard.

KubeBlocks provides a Grafana dashboard for monitoring the Kafka cluster. You can find it at [Kafka Dashboard](https://github.com/apecloud/kubeblocks-addons/tree/main/addons/kafka).

> [!Note]
>
> - Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.
> - set `job` to `kubeblocks` on Grafana dashboard to view the metrics.

### FAQ

#### How to Access Kafka Cluster

##### With Direct Pod Access

To connect to the Kafka cluster, you can use the following command to get the service for connection:

```bash
kubectl get svc -l app.kubernetes.io/instance=kafka-combined-cluster -n default
```

And the excepted output is like below:

```text
NAME                                                         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kafka-combined-cluster-kafka-combine-advertised-listener-0   ClusterIP   10.96.221.254   <none>        9092/TCP   28m
```

You can connect to the Kafka cluster using the `CLUSTER-IP` and `PORT`.

##### With NodePort Service

Currently only `nodeport` and `clusterIp` network modes are supported for Kafka
To access the Kafka cluster using the `nodeport` service, you can create Kafka cluster with the following configuration,  refer to [Kafka Network Modes Example](./cluster-combined-nodeport.yaml) for more details.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: kafka-combine
      stop: false  # set to `false` (or remove this field) to start the component
      services:
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
