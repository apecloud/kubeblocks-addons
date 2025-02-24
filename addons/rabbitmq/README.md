# RabbitMQ

RabbitMQ is an open-source and lightweight message broker which supports multiple messaging protocols.

## Features In KubeBlocks

### Lifecycle Management

|   Topology       | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| cluster     | Yes                    | Yes                   | Yes              | Yes       | Yes        | No       | Yes    | N/A     |

### Versions

| Major Versions | Description |
|---------------|-------------|
| 3.8 | 3.8.14|
| 3.9 | 3.9.29|
| 3.10 | 3.10.25|
| 3.11 | 3.11.28|
| 3.12 | 3.12.14|
| 3.13 | 3.13.2, 3.13.7|

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- RabbitMQ Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### [Create](cluster.yaml)

Create a rabbitmq cluster with 3 replicas:

```yaml
# cat examples/rabbitmq/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: rabbitmq-cluster
  namespace: default
spec:
  # Specifies the behavior when a Cluster is deleted.
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies a list of ClusterComponentSpec objects used to define the individual components that make up a Cluster. This field allows for detailed configuration of each component within the Cluster.
  # Note: `shardingSpecs` and `componentSpecs` cannot both be empty; at least one must be defined to configure a cluster.
  # ClusterComponentSpec defines the specifications for a Component in a Cluster.
  componentSpecs:
    - name: rabbitmq
      componentDef: rabbitmq
      # The serviceVersion is used to determine the version of the Cluster. If the serviceVersion is not specified, the default value is the ServiceVersion defined in ComponentDefinition.
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [3.10.25,3.11.28,3.12.14,3.13.2,3.13.7,3.8.14,3.9.29]
      serviceVersion: 3.13.7
      # Recommended to set `replicas` to [3,5,7]
      # All data/state is replicated across all replicas.
      replicas: 3
      # Specifies the resources required by the Component.
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
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
                # Set the storage size as needed
                storage: 20Gi

```

```bash
kubectl apply -f examples/rabbitmq/cluster.yaml
```

> [!Important]
> Unlike others, on creating the cluster, this example creates a ServiceAccount, Role, and RoleBinding for the RabbitMQ cluster.
> RabbitMQ needs `peer discovery` role to create events and get endpoints. This is essential for discovering other RabbitMQ nodes and forming a cluster.
> When `PulicyRule` API is ready, rules defined in the `Role` can be defined in the `ComponentDefintion.Spec.PolicyRule`. Such that KubeBlocks will automatically create and manage the `Role` and `RoleBinding` for the component.

### Horizontal scaling

> [!Important]
> RabbitMQ quorum queue are designed based on the **Raft consensus algorithm**.
> Make sure to have an odd number of replicas, such as 3, 5, 7, to avoid split-brain scenarios, after scaling out/in the cluster.

#### [Scale-out](scale-out.yaml)

Horizontal scaling out cluster by adding ONE more  replica:

```yaml
# cat examples/rabbitmq/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rabbitmq-scale-out
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rabbitmq-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: rabbitmq
    # Specifies the replica changes for scaling out components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/rabbitmq/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in cluster by deleting ONE replica:

```yaml
# cat examples/rabbitmq/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rabbitmq-scale-in
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rabbitmq-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: rabbitmq
    # Specifies the replica changes for scaling out components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/rabbitmq/scale-in.yaml
```

On scale-in, the replica with the highest number (if not specified in particular) will be stopped, removed and be `forget_cluster_node` from the cluster.

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
spec:
  componentSpecs:
    - name: rabbitmq
      componentDef: rabbitmq
      replicas: 3 # Update `replicas` to your desired number
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/rabbitmq/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rabbitmq-verticalscaling
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rabbitmq-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: rabbitmq
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/rabbitmq/verticalscale.yaml
```

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
spec:
  componentSpecs:
    - name: rabbitmq
      componentDef: rabbitmq
      replicas: 3
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

```yaml
# cat examples/rabbitmq/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rabbitmq-volumeexpansion
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rabbitmq-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: rabbitmq
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/rabbitmq/volumeexpand.yaml
```

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
spec:
  componentSpecs:
    - name: rabbitmq
      componentDef: rabbitmq
      replicas: 3
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                # specify new size, and make sure it is larger than the current size
                storage: 30Gi
```

### [Restart](restart.yaml)

Restart the specified components in the cluster:

```yaml
# cat examples/rabbitmq/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rabbitmq-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rabbitmq-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: rabbitmq

```

```bash
kubectl apply -f examples/rabbitmq/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/rabbitmq/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rabbitmq-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rabbitmq-cluster
  type: Stop

```

```bash
kubectl apply -f examples/rabbitmq/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```yaml
# cat examples/rabbitmq/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rabbitmq-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rabbitmq-cluster
  type: Start

```

```bash
kubectl apply -f examples/rabbitmq/start.yaml
```

### Expose

#### [Enable](expose-enable.yaml)

```yaml
# cat examples/rabbitmq/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rabbitmq-expose-enable
  namespace: default
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rabbitmq-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: rabbitmq
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      # Determines how the Service is exposed. Defaults to 'ClusterIP'.
      # Valid options are `ClusterIP`, `NodePort`, and `LoadBalancer`.
      serviceType: LoadBalancer
      ports:
        - name: managment
          port: 15672
          targetPort: management
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
kubectl apply -f examples/rabbitmq/expose-enable.yaml
```

#### [Disable](expose-disable.yaml)

```yaml
# cat examples/rabbitmq/expose-disable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rabbitmq-expose-disable
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rabbitmq-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: rabbitmq
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      serviceType: LoadBalancer
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Disable
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Expose

```

```bash
kubectl apply -f examples/rabbitmq/expose-disable.yaml
```

#### Expose SVC using Cluster API

Alternatively, you may expose service by updating `spec.services`

```yaml
spec:
  services:
    # add annotation for cloud loadbalancer if
    # services.spec.type is LoadBalancer
    # here we use annotation for alibaba cloud for example
  - annotations:
      # aws annotations
      service.beta.kubernetes.io/aws-load-balancer-type: nlb  # Use Network Load Balancer
      service.beta.kubernetes.io/aws-load-balancer-internal: "true"  # or "false" for internet
    componentSelector: rabbitmq
    name: rabbitmq-vpc
    serviceName: rabbitmq-vpc
    spec:  # defines the behavior of a K8s service.
      ipFamilyPolicy: PreferDualStack
      ports:
      - name: tcp-rabbitmq
        # port to expose
        port: 15672 # port 15672 for rabbitmq management console
        protocol: TCP
        targetPort: management
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

### [Reconfigure](reconfigure.yaml)

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```yaml
# cat examples/rabbitmq/reconfigure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rabbitmq-reconfiguring
  namespace: default
spec:
  # Specifies the type of this operation.
  type: Reconfiguring
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mycluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: rabbitmq
   # Contains a list of ConfigurationItem objects, specifying the Component's configuration template name, upgrade policy, and parameter key-value pairs to be updated.
    configurations:
      # Sets the parameters to be updated. It should contain at least one item.
      # The keys are merged and retained during patch operations.
    - keys:
        # Represents the unique identifier for the ConfigMap.
      - key: rabbitmq.conf
        # Defines a list of key-value pairs for a single configuration file.
        # These parameters are used to update the specified configuration settings.
        parameters:
          # Represents the name of the parameter that is to be updated.
          # `channel_max` is a static parameter in rabbitmq
        - key: ssl_handshake_timeout
          # Represents the parameter values that are to be updated.
          # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
          value: "2000"
      # Specifies the name of the configuration template.
      name: config
```

```bash
kubectl apply -f examples/rabbitmq/reconfigure.yaml
```

This example will change the `channel_max` to `2000`.

> In RabbitMQ, the `channel_max` parameter is used to set the maximum number of channels that a client can open on a single connection. It is a static parameter, so the change will take effect after restarting the database.

To verify the change, you may login to any replica and run the following command:

```bash
rabbitmq-diagnostics environment
```

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

##### Step 1. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/rabbitmq/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: rabbitmq-cluster-pod-monitor
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
      port: prometheus
      scheme: http
  namespaceSelector:
    matchNames:
      - default
  selector:
    matchLabels:
      app.kubernetes.io/instance: rabbitmq-cluster
      apps.kubeblocks.io/component-name: rabbitmq
```

```bash
kubectl apply -f examples/rabbitmq/pod-monitor.yaml
```

It sets path to `/metrics` and port to `prometheus` (for container port `15692`).

```yaml
    - path: /metrics
      port: prometheus
      scheme: http
```

##### Step 2. Access the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard.
You can import the dashboard from [Grafana RabbitMQ-Overview](https://grafana.com/grafana/dashboards/10991-rabbitmq-overview/).

> [!Note]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster rabbitmq-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete -f examples/rabbitmq/cluster.yaml
```

## Appendix

### How to access RabbitMQ Management Console

To access the RabbitMQ Management console (at port `15672`), you can:

- Option 1. Expose the RabbitMQ cluster service:

```yaml
# cat examples/rabbitmq/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rabbitmq-expose-enable
  namespace: default
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: rabbitmq-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: rabbitmq
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      # Determines how the Service is exposed. Defaults to 'ClusterIP'.
      # Valid options are `ClusterIP`, `NodePort`, and `LoadBalancer`.
      serviceType: LoadBalancer
      ports:
        - name: managment
          port: 15672
          targetPort: management
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
kubectl apply -f examples/rabbitmq/expose-enable.yaml
```

- Option 2. Use port-forwarding:

```bash
kubectl port-forward svc/rabbitmq-cluster-rabbitmq 15672:15672
```

Then log in to the RabbitMQ Management console at `http://<localhost>:<port>/` with the user and password.

The user and password can be found in the cluster secrets named after `<clusterName>-<cmpName>-account-<accountName>`. In this case, the secret name is `rabbitmq-cluster-rabbitmq-account-root`.

