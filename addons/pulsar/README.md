# Pulsar

Apache® Pulsar™ is an open-source, distributed messaging and streaming platform built for the cloud.
Pulsar's architecture is designed to provide scalability, reliability, and flexibility. It consists of several key components:

- Brokers: These are stateless components responsible for handling incoming messages from producers, dispatching messages to consumers, and managing communication with the configuration store for coordination tasks. They also interface with Bookkeeper instances (bookies) for message storage and rely on a cluster-specific Zookeeper cluster for certain tasks.

- Apache Bookkeeper (aka bookies): It handles the persistent storage of messages. Bookkeeper is a distributed write-ahead log (WAL) system that provides several advantages, including the ability to handle many independent logs (ledgers), efficient storage for sequential data, and guarantees read consistency even in the presence of system failures.

- Zookeeper: Pulsar uses Zookeeper clusters for coordination tasks between Pulsar clusters and for cluster-level configuration and coordination.

Optional components include:

- Pulsar Proxy: It is an optional gateway. It is typically used in scenarios where direct access to brokers is restricted due to network policies or security requirements. The proxy helps in managing client connections and forwarding requests to the appropriate brokers, providing an additional layer of security and simplifying network configurations.

- Bookies Recovery: It is an optional component that helps in recovering data from failed bookies. It is used in scenarios where a bookie fails and data needs to be recovered from other bookies in the cluster.

## Features In KubeBlocks

### Lifecycle Management

| Topology | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Basic/Enhanced | Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | No      |

- Basic Mode: Includes the basic features of Pulsar, such as brokers, bookies, and Zookeeper.
- Enhanced Mode: Includes additional components like Pulsar Proxy and Bookies Recovery.


### Versions

| Major Versions | Versions |
|----------|-------|
| 2.11.x   | 2.11.2 |
| 3.0.x    | 3.0.2 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Pulsar Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### Create

#### Basic Mode

Create a pulsar cluster of `Basic` mode.

```yaml
# cat examples/pulsar/cluster-basic.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pulsar-basic-cluster
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
  # The value must be `pulsar` to create a Pulsar Cluster
  clusterDef: pulsar
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  topology: pulsar-basic-cluster
  # Defines a list of additional Services that are exposed by a Cluster.
  services:
    - name: broker-bootstrap
      serviceName: broker-bootstrap
      componentSelector: broker
      spec:
        type: ClusterIP
        ports:
          - name: pulsar
            port: 6650
            targetPort: 6650
          - name: http
            port: 80
            targetPort: 8080
          - name: kafka-client
            port: 9092
            targetPort: 9092
    - name: zookeeper
      serviceName: zookeeper
      componentSelector: zookeeper
      spec:
        type: ClusterIP
        ports:
          - name: client
            port: 2181
            targetPort: 2181
  componentSpecs:
    - name: broker
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [2.11.2,3.0.2]
      serviceVersion: 3.0.2
      replicas: 1
      env:
        - name: KB_PULSAR_BROKER_NODEPORT
          value: "false"
      resources:
        limits:
          cpu: "1"
          memory: "512Mi"
        requests:
          cpu: "200m"
          memory: "512Mi"
    - name: bookies
      serviceVersion: 3.0.2
      replicas: 4
      resources:
        limits:
          cpu: "1"
          memory: "512Mi"
        requests:
          cpu: "200m"
          memory: "512Mi"
      volumeClaimTemplates:
        - name: ledgers
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 8Gi
        - name: journal
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 8Gi
    - name: zookeeper
      serviceVersion: 3.0.2
      replicas: 1
      resources:
        limits:
          cpu: "1"
          memory: "512Mi"
        requests:
          cpu: "100m"
          memory: "512Mi"
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 8Gi
```

```bash
kubectl apply -f examples/pulsar/cluster-basic.yaml
```

A cluster with one brokers, four bookies, and one zookeepers will be created.
The Zookeeper component will be created apriori, and the Broker and Bookies components will be created after the Zookeeper component is `RUNNING`.

#### Enhanced Mode

Create a pulsar cluster of `Enhanced` mode.

```yaml
# cat examples/pulsar/cluster-enhanced.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pulsar-enhanced-cluster
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
  # The value must be `pulsar` to create a Pulsar Cluster
  clusterDef: pulsar
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  topology: pulsar-enhanced-cluster
  # Defines a list of additional Services that are exposed by a Cluster.
  services:
    - name: broker-bootstrap
      serviceName: broker-bootstrap
      componentSelector: broker
      spec:
        type: ClusterIP
        ports:
          - name: pulsar
            port: 6650
            targetPort: 6650
          - name: http
            port: 80
            targetPort: 8080
          - name: kafka-client
            port: 9092
            targetPort: 9092
    - name: zookeeper
      serviceName: zookeeper
      componentSelector: zookeeper
      spec:
        type: ClusterIP
        ports:
          - name: client
            port: 2181
            targetPort: 2181
  componentSpecs:
    - name: proxy
      serviceVersion: 3.0.2
      replicas: 3
      resources:
        limits:
          cpu:
          memory: "512Mi"
        requests:
          cpu: "200m"
          memory: "512Mi"
    - name: bookies-recovery
      serviceVersion: 3.0.2
      replicas: 1
      resources:
        limits:
          cpu:
          memory: "512Mi"
        requests:
          cpu: "200m"
          memory: "512Mi"
    - name: broker
      serviceVersion: 3.0.2
      replicas: 1
      resources:
        limits:
          cpu:
          memory: "512Mi"
        requests:
          cpu: "200m"
          memory: "512Mi"
    - name: bookies
      serviceVersion: 3.0.2
      replicas: 4
      resources:
        limits:
          cpu:
          memory: "512Mi"
        requests:
          cpu: "200m"
          memory: "512Mi"
      volumeClaimTemplates:
        - name: ledgers
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 8Gi
        - name: journal
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 8Gi
    - name: zookeeper
      serviceVersion: 3.0.2
      replicas: 1
      resources:
        limits:
          cpu:
          memory: "512Mi"
        requests:
          cpu: "100m"
          memory: "512Mi"
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 8Gi

```

```bash
kubectl apply -f examples/pulsar/cluster-enhanced.yaml
```

A cluster with one brokers, four bookies, one bookies recovery, three proxy, and one zookeepers will be created.

And these components will be created in the following order: Zookeeper and Bookies Recovery, Bookies and Broker, finally Proxy.

### Horizontal scaling

> [!IMPORTANT]
> Please check how many replicas are allowed for each component in the cluster before scaling out/in.

A Pulsar cluster can scale to handle hundreds of brokers, depending on the workload and the resources available.
Suggested practices are:

- Start with a smaller number (3-5 brokers) for most deployments
- Scale horizontally as needed based on metrics
- Monitor performance and resource utilization

Here is an example of scale-out and scale-in operations for the Broker component.

#### Scale-out

Horizontal scaling out by adding ONE more replica for Broker component:

```yaml
# cat examples/pulsar/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pulsar-broker-scale-out
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pulsar-basic-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - proxy
    # - bookies-recovery
    # - broker
    # - bookies
    # - zookeeper
  - componentName: broker
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/pulsar/scale-out.yaml
```

#### Scale-in

Horizontal scaling in PostgreSQL cluster by deleting ONE replica:

```yaml
# cat examples/pulsar/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pulsar-broker-scale-in
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pulsar-basic-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - proxy
    # - bookies-recovery
    # - broker
    # - bookies
    # - zookeeper
  - componentName: broker
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/pulsar/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: broker
      componentDef: pulsar-broker
      serviceVersion: 3.0.2
      replicas: 1 # update to your desired number
      ...
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/pulsar/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pulsar-verticalscaling
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pulsar-basic-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
    # - proxy
    # - bookies-recovery
    # - broker
    # - bookies
    # - zookeeper
  - componentName: broker
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/pulsar/verticalscale.yaml
```

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: broker
      componentDef: pulsar-broker
      serviceVersion: 3.0.2
      resources:
        requests:
          cpu: "1"       # Update the resources to your need.
          memory: "2Gi"  # Update the resources to your need.
        limits:
          cpu: "2"       # Update the resources to your need.
          memory: "4Gi"  # Update the resources to your need.
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/pulsar/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pulsar-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pulsar-basic-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
    # - proxy
    # - bookies-recovery
    # - broker
    # - bookies
    # - zookeeper
  - componentName: broker

```

```bash
kubectl apply -f examples/pulsar/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved.

You may stop specific components or the entire cluster. Here is an example of stopping the cluster.

```yaml
# cat examples/pulsar/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pulsar-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pulsar-basic-cluster
  type: Stop
  # Lists Components to be stopped. ComponentOps specifies the Component to be operated on.
  # stop:
    # Specifies the name of the Component.
    # - proxy
    # - bookies-recovery
    # - broker
    # - bookies
    # - zookeeper
  # - componentName: broker

```

```bash
kubectl apply -f examples/pulsar/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/pulsar/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pulsar-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pulsar-basic-cluster
  type: Start
```

```bash
kubectl apply -f examples/pulsar/start.yaml
```

### Reconfigure

Configure parameters with the specified components in the cluster

```yaml
# cat examples/pulsar/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: pulsar-reconfiguring
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pulsar-basic-cluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
    # - proxy
    # - bookies-recovery
    # - broker
    # - bookies
    # - zookeeper
  - componentName: bookies
   # Contains a list of ConfigurationItem objects, specifying the Component's configuration template name, upgrade policy, and parameter key-value pairs to be updated.
    configurations:
      # Sets the parameters to be updated. It should contain at least one item.
      # The keys are merged and retained during patch operations.
    - keys:
        # Represents the unique identifier for the ConfigMap.
      - key: bookkeeper.conf
        # Defines a list of key-value pairs for a single configuration file.
        # These parameters are used to update the specified configuration settings.
        parameters:
          # Represents the name of the parameter that is to be updated.
        - key: lostBookieRecoveryDelay
          # Represents the parameter values that are to be updated.
          # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
          value: "1000"
      # Specifies the name of the configuration template.
      name: bookies-config
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring

```

```bash
kubectl apply -f examples/pulsar/configure.yaml
```

It sets `lostBookieRecoveryDelay` in bookies to `1000`.
> [!WARNING]
> As `lostBookieRecoveryDelay` is defined as a static parameter, all bookies replicas will be restarted to make sure the reconfiguration takes effect.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster pulsar-basic-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster pulsar-basic-cluster
```

## Appendix

There are some interesting features we developed for Pulsar.

### 1. Reuse an existing ZK Cluster through service reference

As mentioned earlier, a Pulsar Cluster needs three components: Broker, Bookies and Zookeeper. As Zookeeper(ZK) is a widely used component, there are cases you already have one or more ZK clusters before creating a Pulsar Cluster, and do not want to create another ZK cluster. To handle such cases, KubeBlocks provides `Service Reference` API to refer a service, provided by either internal/external (KubeBlocks) clusters.

#### 1.1 Refer to an Internal (to KubeBlocks) Zookeeper Cluster

Suppose you have created ZK Cluster name 'zk-cluster' managed by Kubeblocks, or you can create one if not:

```yaml
kubectl create -f examples/pulsar/zookeeper-cluster.yaml
```

To create a Pulsar Cluster referring to an existing ZK Cluster, you may use

```yaml
kubectl create -f examples/pulsar/cluster-service-refer.yaml
```

The key changes are, we add a API `serviceRefs` to express such inter-cluster service reference for each component, and we don't need to specify the Zookeeper component in the Pulsar Cluster.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: proxy
      componentDef: pulsar-proxy
      serviceVersion: 3.0.2
      # Defines a list of ServiceRef for a Component, enabling access to both
      # external services and
      # Services provided by other Clusters.
      serviceRefs:
        - name: pulsarZookeeper    # identifier of the service reference declaration, defined in `componentDefinition.spec.serviceRefDeclarations[*].name`
          namespace: default       # Specifies the namespace of the referenced Cluster
          clusterServiceSelector:  # References a service provided by another KubeBlocks Cluster
            cluster: zk-cluster    # Cluster Name
            service:
              component: zookeeper # Component Name
              service: zookeeper   # service name defined in Zookeeper ComponentDefinition
              port: "2881"         # port
      replicas: 3
      ...
```

#### 1.2 Refer to an External (to KubeBlocks) Zookeeper Cluster

Create a `ServiceDescriptor` for the external Zookeeper Cluster, specifying the service name and port.

```yaml
kubectl apply -f examples/pulsar/zookeeper-service-descriptor.yaml
```

Create a pulsar cluster with specified `serviceRefs.serviceDescriptor`, when referencing a service provided by external sources.

```yaml
# cat examples/pulsar/cluster-service-descriptor.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pulsar-service-descriptor
  namespace: default
spec:
  terminationPolicy: Delete
  services:
    - name: broker-bootstrap
      serviceName: broker-bootstrap
      componentSelector: broker
      spec:
        type: ClusterIP
        ports:
          - name: pulsar
            port: 6650
            targetPort: 6650
          - name: http
            port: 80
            targetPort: 8080
          - name: kafka-client
            port: 9092
            targetPort: 9092
  componentSpecs:
    - name: broker
      componentDef: pulsar-broker
      serviceVersion: 3.0.2
      env:
        - name: KB_PULSAR_BROKER_NODEPORT
          value: "false"
      serviceRefs:
        - name: pulsarZookeeper
          namespace: default
          serviceDescriptor: zookeeper-sd
      replicas: 1
      resources:
        limits:
          cpu:
          memory: "512Mi"
        requests:
          cpu: "200m"
          memory: "512Mi"
    - name: bookies
      componentDef: pulsar-bookkeeper
      serviceVersion: 3.0.2
      serviceRefs:
        - name: pulsarZookeeper
          namespace: default
          serviceDescriptor: zookeeper-sd
      replicas: 4
      resources:
        limits:
          cpu:
          memory: "512Mi"
        requests:
          cpu: "200m"
          memory: "512Mi"
      volumeClaimTemplates:
        - name: ledgers
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 8Gi
        - name: journal
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 8Gi
```

```bash
kubectl apply -f examples/pulsar/cluster-service-descriptor.yaml
```

The key change is , we add a API `serviceRefs.serviceDescriptor` to express such inter-cluster service reference

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: proxy
      componentDef: pulsar-proxy
      serviceVersion: 3.0.2
      # Defines a list of ServiceRef for a Component, enabling access to both
      # external services and
      # Services provided by other Clusters.
      serviceRefs:
        - name: pulsarZookeeper    # identifier of the service reference declaration, defined in `componentDefinition.spec.serviceRefDeclarations[*].name`
          namespace: default       # Specifies the namespace of the referenced ServiceDescriptor
          serviceDescriptor: zookeeper-sd # ServiceDescriptor Name
      ...
```

### 2. Enable NodePort for Pulsar

By default, Pulsar does not expose any service to the external network. If you want to expose the service to the external network, you can enable the NodePort service.

```yaml
kubectl apply -f examples/pulsar/cluster-nodeport.yaml
```

The key difference are:

1. set service type to `NodePort` (default is `ClusterIP`)
1. set env `KB_PULSAR_BROKER_NODEPORT` to `TRUE`, it will set up the advertised listener to the NodePort service.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  terminationPolicy: Delete
  services:
    - name: broker-bootstrap
      serviceName: broker-bootstrap
      componentSelector: broker
      spec:
        type: NodePort       # set svc type to NodePort
        ports:
          - name: pulsar
            port: 6650
            targetPort: 6650
    - name: zookeeper
  componentSpecs:
    - name: broker
      componentDef: pulsar-broker
      serviceVersion: 3.0.2
      env:
        - name: KB_PULSAR_BROKER_NODEPORT  # set KB_PULSAR_BROKER_NODEPORT to true
          value: "true"
      services:
        - name: advertised-listener
          serviceType: NodePort           # set svc type to NodePort
          podService: true
    - name: bookies
    - name: zookeeper
    ...
