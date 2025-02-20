# Zookeeper

Apache Zookeeper is a centralized service for maintaining configuration information, naming, providing distributed synchronization, and providing group services.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | No      |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Full Backup | zoocreeper | uses `zoocreeper` tool to create a backup |

### Versions

| Versions |
|----------|
| 3.4.14,3.6.4,3.7.2,3.8.4,3.9.2 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Zookeeper Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### [Create](cluster.yaml)

Create a zookeeper cluster with three replicas, one leader replica and two follower replicas:

```yaml
# cat examples/zookeeper/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: zookeeper-cluster
  namespace: demo
spec:
  # Specifies the behavior when a Cluster is deleted.
  # Valid options are: [DoNotTerminate, Delete, WipeOut] (`Halt` is deprecated since KB 0.9)
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [3.4.14,3.6.4,3.7.2,3.8.4,3.9.2]
      serviceVersion: "3.9.2"
      # Update `replicas` to your need.
      replicas: 3
      # Specifies the resources required by the Component.
      resources:
        limits:
          cpu: '0.5'
          memory: 0.5Gi
        requests:
          cpu: '0.5'
          memory: 0.5Gi
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
        # Refers to the name of a volumeMount defined in
        # `componentDefinition.spec.runtime.containers[*].volumeMounts
        - name: log
          spec:
            # The name of the StorageClass required by the claim.
            # If not specified, the StorageClass annotated with
            # `storageclass.kubernetes.io/is-default-class=true` will be used by default
            storageClassName: ""
            accessModes:
            - ReadWriteOnce
            resources:
              requests:
                storage: 2Gi

```

```bash
kubectl apply -f examples/zookeeper/cluster.yaml
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out cluster by adding ONE more `OBSERVER` replica:

```yaml
# cat examples/zookeeper/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: zk-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: zookeeper-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: zookeeper
    # Specifies the replica changes for scaling out components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/zookeeper/scale-out.yaml
```

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe ops zk-scale-out
```

> [!WARNING] As defined, Zookeeper Cluster will be restarted on horizontal scaling. To make sure all config are loaded properly.

After scaling, cluster server list in Zookeeper configuration file `zoo.cfg` will be updated :

```text
# cluster server list
server.0 = zookeeper-cluster-zookeeper-0.zookeeper-cluster-zookeeper-headless.default.svc.cluster.local:2888:3888:participant
server.1
    = zookeeper-cluster-zookeeper-1.zookeeper-cluster-zookeeper-headless.default.svc.cluster.local:2888:3888:participant
server.2
    = zookeeper-cluster-zookeeper-2.zookeeper-cluster-zookeeper-headless.default.svc.cluster.local:2888:3888:participant
server.3
    = zookeeper-cluster-zookeeper-3.zookeeper-cluster-zookeeper-headless.default.svc.cluster.local:2888:3888:observer
```

Information for `server.3` is added on scaling out.

#### [Scale-in](scale-in.yaml)

Horizontal scaling in cluster by deleting ONE replica:

```yaml
# cat examples/zookeeper/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: zk-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: zookeeper-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: zookeeper
    # Specifies the replica changes for scaling out components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/zookeeper/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: zookeeper-cluster
  namespace: demo
spec:
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
      replicas: 3 # Update `replicas` to 1 for scaling in, and to 3 for scaling out
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/zookeeper/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: zookeeper-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: zookeeper-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: zookeeper
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/zookeeper/verticalscale.yaml
```

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: zookeeper-cluster
  namespace: demo
spec:
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
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
# cat examples/zookeeper/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: zookeeper-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: zookeeper-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: zookeeper
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/zookeeper/volumeexpand.yaml
```

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: zookeeper-cluster
  namespace: demo
spec:
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
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
      volumeClaimTemplates:
        - name: log
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                # specify new size, and make sure it is larger than the current size
                storage: 20Gi
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```yaml
# cat examples/zookeeper/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: zookeeper-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: zookeeper-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: zookeeper

```

```bash
kubectl apply -f examples/zookeeper/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```yaml
# cat examples/zookeeper/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: zookeeper-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: zookeeper-cluster
  type: Stop

```

```bash
kubectl apply -f examples/zookeeper/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: zookeeper-cluster
  namespace: demo
spec:
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
      stop: true  # set stop `true` to stop the component
      replicas: 3
```

### [Start](start.yaml)

Start the stopped cluster

```yaml
# cat examples/zookeeper/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: zookeeper-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: zookeeper-cluster
  type: Start

```

```bash
kubectl apply -f examples/zookeeper/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: zookeeper-cluster
  namespace: demo
spec:
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 3
```

### [Reconfigure](configure.yaml)

Configure parameters with the specified components in the cluster:

```yaml
# cat examples/zookeeper/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: zookeeper-reconfiguring
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: zookeeper-cluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: zookeeper
   # Contains a list of ConfigurationItem objects, specifying the Component's configuration template name, upgrade policy, and parameter key-value pairs to be updated.
    configurations:
      # Sets the parameters to be updated. It should contain at least one item.
      # The keys are merged and retained during patch operations.
    - keys:
        # Represents the unique identifier for the ConfigMap.
      - key: zoo.cfg
        # Defines a list of key-value pairs for a single configuration file.
        # These parameters are used to update the specified configuration settings.
        parameters:
          # Represents the name of the parameter that is to be updated.
        - key: syncLimit
          # Represents the parameter values that are to be updated.
          # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
          value: '10'
      # Specifies the name of the configuration template.
      name: zookeeper-config
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring

```

```bash
kubectl apply -f examples/zookeeper/configure.yaml
```

`syncLimit` is a configuration parameter that defines the maximum number of ticks a Zookeeper follower can lag behind the leader before it's considered out of sync and must resync with the leader.

In this example updates `syncLimit` to `10` (default to `5` ticks). Increase it for slower networks or larger clusters, and decrease for tighter consistency requirements. Its common range: 2-10 ticks.

To verify the changes, you may log into an Zookeeper instance to check the configuration changes:

```bash
# 2181 is the clientPort
echo "conf" | nc localhost 2181
```

### [Backup](backup.yaml)

> [!NOTE] Before you start, please create a `BackupRepo` to store the backup data. Refer to [BackupRepo](../docs/create-backuprepo.md) for more details.

The method `zoocreeper` uses `zoocreeper` tool to create a compressed backup. You may create a backup using:

```yaml
# cat examples/zookeeper/backup.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: zk-cluster-backup
  namespace: demo
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - zoocreeper
  backupMethod: zoocreeper
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: zookeeper-cluster-zookeeper-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete
```

```bash
kubectl apply -f examples/zookeeper/backup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -l app.kubernetes.io/instance=zookeeper-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

### [Restore](restore.yaml)

To restore a new cluster from a Backup:

```yaml
# cat examples/zookeeper/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: zk-cluster-restore
  namespace: demo
  annotations:
    # zk-cluster-backup is the backup name.
    kubeblocks.io/restore-from-backup: '{"zookeeper":{"name":"zk-cluster-backup","namespace":"default","volumeRestorePolicy":"Parallel"}}'
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: zookeeper
      componentDef: zookeeper
      serviceVersion: "3.9.2"
      replicas: 3
      resources:
        limits:
          cpu: '0.5'
          memory: 0.5Gi
        requests:
          cpu: '0.5'
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
        - name: log
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 2Gi
```

```bash
kubectl apply -f examples/zookeeper/restore.yaml
```

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

##### Step 1. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/zookeeper/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: zk-cluster-pod-monitor
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
      app.kubernetes.io/instance: zookeeper-cluster
      apps.kubeblocks.io/component-name: zookeeper
```

```bash
kubectl apply -f examples/zookeeper/pod-monitor.yaml
```

It sets path to `/metrics` and port to `metrics` (for container port `7000`).

```yaml
  - path: /metrics
    port: metrics
    scheme: http
```

##### Step 2. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard, e.g. using etcd dashboard from [Grafana](https://grafana.com/grafana/dashboards).

> [!Note]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster zookeeper-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster zookeeper-cluster
```
