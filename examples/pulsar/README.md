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

```bash
kubectl apply -f examples/pulsar/cluster-basic.yaml
```

A cluster with one brokers, four bookies, and one zookeepers will be created.
The Zookeeper component will be created apriori, and the Broker and Bookies components will be created after the Zookeeper component is `RUNNING`.

#### Enhanced Mode

Create a pulsar cluster of `Enhanced` mode.

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

#### [Scale-out](scale-out.yaml)

Horizontal scaling out by adding ONE more replica for Broker component:

```bash
kubectl apply -f examples/pulsar/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in PostgreSQL cluster by deleting ONE replica:

```bash
kubectl apply -f examples/pulsar/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pulsar-basic-cluster
  namespace: default
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: broker
      componentDef: pulsar-broker
      serviceVersion: 3.0.2
      replicas: 1 # update to your desired number
      ...
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/pulsar/verticalscale.yaml
```

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pulsar-basic-cluster
  namespace: default
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

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/pulsar/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved.

You may stop specific components or the entire cluster. Here is an example of stopping the cluster.

```bash
kubectl apply -f examples/pulsar/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/pulsar/start.yaml
```

### [Reconfigure](configure.yaml)

Configure parameters with the specified components in the cluster

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
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pulsar-service-ref
  namespace: default
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

```bash
kubectl apply -f examples/pulsar/cluster-service-descriptor.yaml
```

The key change is , we add a API `serviceRefs.serviceDescriptor` to express such inter-cluster service reference

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pulsar-service-descriptor
  namespace: default
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
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pulsar-node-port
  namespace: default
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
```