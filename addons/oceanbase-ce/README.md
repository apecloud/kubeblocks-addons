# OceanBase

OceanBase Database is an enterprise-level native distributed database independently developed by Ant Group.[^2]

## Features In KubeBlocks

### Lifecycle Management

|   Topology       | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| distribution     | Yes                    | Yes                   | No                | Yes       | Yes        | Yes       | Yes    | N/A      |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Backup [^1] | full   | Backs up all macro-blocks.                |
| Restore     | full   | Restore a new cluster from a full backup. |

### Versions

| Service Version | Description |
|-----------------|-------------|
| 4.3.0           | OceanBase 4.3.0.1-100000242024032211 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- OceanBase CE Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### Create

Create a distributed oceanbase cluster

```yaml
# cat examples/oceanbase-ce/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: ob-cluster
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
  # The value must be `oceanbase-ce` to create a OceanBase Cluster
  clusterDef: oceanbase-ce
  # Specifies the name of the ClusterTopology to be used when creating the
  # Cluster.
  # Valid options are: [distribution]
  topology: distribution
  # Specifies a list of ClusterComponentSpec objects used to define the
  # individual Components that make up a Cluster.
  # This field allows for detailed configuration of each Component within the Cluster
  componentSpecs:
    - name: oceanbase
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [4.3.0]
      serviceVersion: 4.3.0
      # Determines whether metrics exporter information is annotated on the
      # Component's headless Service.
      # Valid options are [true, false]
      disableExporter: false
      # List of environment variables to add.
      # These environment variables will be placed AFTER the environment variables
      # declared in the Pod.
      # Some engine specific ENVs can be define here.
      env:
      - name: ZONE_COUNT  # number of zones, default to 3, immutable
        value: "1"
      - name: OB_CLUSTER_ID # set cluster_id of observer, default to 1, immutable
        value: "1"
      # Specifies the desired number of replicas in the Component
      replicas: 1
      # Specifies the resources required by the Component
      resources:
        limits:
          cpu: "3"
          memory: "4Gi"
        requests:
          cpu: "3"
          memory: "4Gi"
      volumeClaimTemplates:
      # Refers to the name of a volumeMount defined in
      # `componentDefinition.spec.runtime.containers[*].volumeMounts
        - name: data-file # data-file for sstable, slog, sort_dir, etc
          spec:
            # The name of the StorageClass required by the claim.
            # If not specified, the StorageClass annotated with
            # `storageclass.kubernetes.io/is-default-class=true` will be used.
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: "50Gi"
        - name: data-log # data-log for clog, ilog
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: "50Gi"
        - name: log # log for running logs, observer.log, rootservice.log
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: "20Gi"
        - name: workdir # workdir for working directory, to save some meta and folder info
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: "1Gi"

```

```bash
kubectl apply -f examples/oceanbase-ce/cluster.yaml
```

Optionally, you can create a cluster using HostNetwork mode, by turning on the feature-gate.
And KubeBlocks will allocate AVAILABLE ports for the components. Details can be found in file [Create HostNetwork](cluster-hostnetwork.yaml).

```yaml
# snippets of cluster-hostnetwork.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  annotations:
    # `kubeblocks.io/host-network` is a reserved annotation
    # it defines the feature gate to enable the host-network for specified components or shardings.
    kubeblocks.io/host-network: "oceanbase"
spec:
```

### Horizontal scaling

#### Scale-out

Horizontal scaling out the cluster by adding ONE more replica:

```yaml
# cat examples/oceanbase-ce/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ob-scale-out
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: ob-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: oceanbase
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/oceanbase-ce/scale-out.yaml
```

After applying the operation, you will see a new pod created and the cluster status goes from `Updating` to `Running`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe ops ob-scale-out -n default
```

The newly added replica will be in `Pending` status, and it will be in `Running` status after the operation is completed. By checking the logs of the POD, you can see the progress of the scaling operation.

```bash
kubectl logs -f <pod-name> -n default
```

And you will see the logs once the new replica is added to the cluster.

```bash
| Wait for the server to be ready...
│ Add the server to zone successfully
│ Cluster starts successfully
```

#### Scale-in

Horizontal scaling in the cluster by removing ONE replica:

```yaml
# cat examples/oceanbase-ce/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ob-scale-in
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: ob-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: oceanbase
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/oceanbase-ce/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: oceanbase
      serviceVersion: "4.3.0"
      disableExporter: false
      replicas: 3 # increase `replicas` for scaling in, and decrease for scaling out
```

### Vertical scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```yaml
# cat examples/oceanbase-ce/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ob-verticalscaling
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: ob-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: oceanbase
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '4'
      memory: 6Gi
    limits:
      cpu: '4'
      memory: 6Gi

```

```bash
kubectl apply -f examples/oceanbase-ce/verticalscale.yaml
```

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: oceanbase
      replicas: 1
      resources:
        requests:
          cpu: "4"       # Update the resources to your need.
          memory: 6Gi"  # Update the resources to your need.
        limits:
          cpu: "4"       # Update the resources to your need.
          memory: "6Gi"  # Update the resources to your need.
```

### Restart

Restart the specified components in the cluster, and instances will be recreated on after another to ensure the availability of the cluster

```yaml
# cat examples/oceanbase-ce/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ob-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: ob-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: oceanbase

```

```bash
kubectl apply -f examples/oceanbase-ce/restart.yaml
```

### Stop

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```yaml
# cat examples/oceanbase-ce/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ob-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: ob-cluster
  type: Stop

```

```bash
kubectl apply -f examples/oceanbase-ce/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: oceanbase
      stop: true  # set stop `true` to stop the component
      replicas: 1
```

### Start

Start the stopped cluster

```yaml
# cat examples/oceanbase-ce/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ob-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: ob-cluster
  type: Start

```

```bash
kubectl apply -f examples/oceanbase-ce/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: oceanbase
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 1
```

### Reconfigure

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```yaml
# cat examples/oceanbase-ce/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ob-reconfiguring
  namespace: default
spec:
  # Specifies the type of this operation.
  type: Reconfiguring
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: ob-cluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: oceanbase
    parameters:
    - key: system_memory
      # Represents the parameter values that are to be updated.
      # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
      value: 2G
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
```

```bash
kubectl apply -f examples/oceanbase-ce/configure.yaml
```

This example will change the `system_memory` to `2Gi`.
> `system_memory` specifies the size of memory reserved by the system tenant. It is a dynamic parameter, so the change will take effect without restarting the database.

```bash
kbcli cluster explain-config pg-cluster # kbcli is a command line tool to interact with KubeBlocks
```

### Backup

> [!IMPORTANT]
> Before you start, please create a `BackupRepo` to store the backup data. Refer to [BackupRepo](../docs/create-backuprepo.md) for more details.

To create a base backup for the cluster, you can apply the following yaml file:

```yaml
# cat examples/oceanbase-ce/backup.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: ob-cluster-backup
  namespace: default
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - full
  backupMethod: full
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: ob-cluster-oceanbase-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete

```

```bash
kubectl apply -f examples/oceanbase-ce/backup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -l app.kubernetes.io/instance=pg-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

Information, such as `path`, `timeRange` about the backup will be recorded into the `Backup` resource.

Alternatively, you can update the `BackupSchedule` to enable the method `full` to schedule full backup periodically.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
metadata:
  name: ob-cluster-oceanbase-backup-schedule
  namespace: default
spec:
  backupPolicyName: ob-cluster-oceanbase-backup-policy
  schedules:
  - backupMethod: full # backup method name, do not chagne
    # ┌───────────── minute (0-59)
    # │ ┌───────────── hour (0-23)
    # │ │ ┌───────────── day of month (1-31)
    # │ │ │ ┌───────────── month (1-12)
    # │ │ │ │ ┌───────────── day of week (0-6) (Sunday=0)
    # │ │ │ │ │
    # 0 18 * * *
    # schedule this job every day at 6:00 PM (18:00).
    cronExpression: 0 18 * * *  # set the cronExpression to your need
    enabled: false  # set to `true` to enable incremental backup
    retentionPeriod: 7d # set the retention period to your need, default is 7 days
```

### Restore

To restore a new cluster from a `Backup`, you can apply the following yaml file:

1. Get the list of accounts and their passwords from the backup:

```bash
kubectl get backup ob-cluster-backup -ojsonpath='{.metadata.annotations.kubeblocks\.io/encrypted-system-accounts}'
```

1. Update `examples/oceanbase-ce/restore.yaml` and set fields quoted with `<ENCRYPTED-SYSTEM-ACCOUNTS>` to your own settings and apply it.

```yaml
# cat examples/oceanbase-ce/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: oceanbase-cluster-restore
  namespace: default
  annotations:
    # NOTE: replace <ENCRYPTED-SYSTEM-ACCOUNTS> with the accounts info from you backup
    kubeblocks.io/restore-from-backup: '{"postgresql":{"encryptedSystemAccounts":"<ENCRYPTED-SYSTEM-ACCOUNTS>","name":"ob-cluster-backup","namespace":"default","volumeRestorePolicy":"Parallel"}}'
spec:
  terminationPolicy: Delete
  clusterDef: oceanbase-ce
  topology: distribution
  componentSpecs:
    - name: oceanbase
      serviceVersion: 4.3.0
      disableExporter: false
      env:
      - name: ZONE_COUNT  # number of zones, default to 3, immutable
        value: "1"
      - name: OB_CLUSTER_ID # set cluster_id of observer, default to 1, immutable
        value: "1"
      # Specifies the desired number of replicas in the Component
      replicas: 1
      # Specifies the resources required by the Component~.
      resources:
        limits:
          cpu: "3"
          memory: "4Gi"
        requests:
          cpu: "3"
          memory: "4Gi"
      volumeClaimTemplates:
      # Refers to the name of a volumeMount defined in
      # `componentDefinition.spec.runtime.containers[*].volumeMounts
        - name: data-file # data-file for sstable, slog, sort_dir, etc
          spec:
            # The name of the StorageClass required by the claim.
            # If not specified, the StorageClass annotated with
            # `storageclass.kubernetes.io/is-default-class=true` will be used.
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: "50Gi"
        - name: data-log # data-log for clog, ilog
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: "50Gi"
        - name: log # log for running logs, observer.log, rootservice.log
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: "20Gi"
        - name: workdir # workdir for working directory, to save some meta and folder info
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: "1Gi"

```

```bash
kubectl apply -f examples/oceanbase-ce/restore.yaml
```

### Expose

Expose a cluster with a new endpoint

#### Enable

```yaml
# cat examples/oceanbase-ce/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: oceanbase-expose-enable
  namespace: default
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: ob-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: oceanbase
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
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Enable
```

```bash
kubectl apply -f examples/oceanbase-ce/expose-enable.yaml
```

#### Disable

```yaml
# cat examples/oceanbase-ce/expose-disable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: oceanbase-expose-disable
  namespace: default
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: ob-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: oceanbase
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      # Determines how the Service is exposed. Defaults to 'ClusterIP'.
      # Valid options are `ClusterIP`, `NodePort`, and `LoadBalancer`.
      serviceType: LoadBalancer
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Disable

```

```bash
kubectl apply -f examples/oceanbase-ce/expose-disable.yaml
```

#### Expose SVC using Cluster API

Alternatively, you may expose service by updating `spec.services`

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  # append service to the list
  services:
    # add annotation for cloud loadbalancer if
    # services.spec.type is LoadBalancer
    # here we use annotation for alibaba cloud for example
  - annotations:
      service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: internet
    componentSelector: oceanbase
    name: oceanbase-vpc
    serviceName: oceanbase-vpc
    spec:  # defines the behavior of a K8s service.
      ipFamilyPolicy: PreferDualStack
      ports:
      - name: sql
        # port to expose
        port: 2881
        protocol: TCP
        targetPort: sql
      # Valid options:[ClusterIP, NodePort, LoadBalancer, ExternalName]
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

#### Create PodMonitor

##### Step 1. Query ScrapePath and ScrapePort

Here is the list of endpoints that can be scraped by Prometheus provided by `obagent`:

```yaml
  podMetricsEndpoints:
    - path: /metrics/stat
      port: http
      scheme: http
    - path: /metrics/ob/basic
      port: http
      scheme: http
    - path: /metrics/ob/extra
      port: http
      scheme: http
    - path: /metrics/node/ob
      port: http
      scheme: http
```

##### Step 2. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/oceanbase-ce/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: ob-cluster-pod-monitor
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
    - path: /metrics/stat
      port: http
      scheme: http
    - path: /metrics/ob/basic
      port: http
      scheme: http
    - path: /metrics/ob/extra
      port: http
      scheme: http
    - path: /metrics/node/ob
      port: http
      scheme: http
  namespaceSelector:
    matchNames:
      - default
  selector:
    matchLabels:
      app.kubernetes.io/instance: ob-cluster
```

```bash
kubectl apply -f examples/oceanbase-ce/pod-monitor.yaml
```

##### Step 3. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard.

There is a pre-configured dashboard for PostgreSQL under the `APPS / OceanBase Mertrics` folder in the Grafana dashboard.

> [!Note]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster ob-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster ob-cluster
```

## References

[^1]: OceanBase Backup, https://en.oceanbase.com/docs/common-oceanbase-database-10000000001231357
