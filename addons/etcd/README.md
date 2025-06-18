# etcd

etcd is a distributed, highly available key-value store designed to securely store data across a cluster of machines. It provides strong consistency guarantees, ensuring that data is reliably replicated and synchronized among all nodes. etcd is commonly used for configuration management, service discovery, and coordinating distributed systems. Its simplicity and robustness make it a critical component in cloud-native environments, particularly within Kubernetes for maintaining cluster state and configuration.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | Yes      |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Full Backup | datafile | using `etcdcl snapshot save` to create snapshot of the etcd cluster's data |

### Versions

| Major Versions | Description |
|---------------|-------------|
| 3.5.x         | 3.5.6,3.5.15|

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- ETCD Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

Create an etcd cluster with three replicas, one leader and two followers.

```yaml
# cat examples/etcd/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: etcd-cluster
  namespace: demo
spec:
  # Specifies the behavior when a Cluster is deleted.
  # Valid options are: [DoNotTerminate, Delete, WipeOut] (`Halt` is deprecated since KB 0.9)
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  componentSpecs:
    - name: etcd
      componentDef: etcd
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      # Valid options are: [3.5.15,3.5.6]
      serviceVersion: 3.5.15
      # Determines whether metrics exporter information is annotated on the
      # Component's headless Service.
      # Valid options are [true, false]
      disableExporter: false
      # Specifies the desired number of replicas in the Component
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
kubectl apply -f examples/etcd/cluster.yaml
```

#### Create with TLS Enabled

To create etcd cluster with TLS enabled,

```yaml
# cat examples/etcd/cluster-with-tls.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: etcd-cluster-tls
  namespace: demo
spec:
  # Specifies the behavior when a Cluster is deleted.
  # Valid options are: [DoNotTerminate, Delete, WipeOut] (`Halt` is deprecated since KB 0.9)
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  componentSpecs:
    - name: etcd
      componentDef: etcd
      # A boolean flag that indicates whether the Component should use Transport
      # Layer Security (TLS)
      # for secure communication.
      # Valid options are: [true,false]
      tls: true   # set TLS to true
      issuer:     # if TLS is True, this filed is required.
        name: KubeBlocks  # set Issuer to [KubeBlocks, UserProvided].
      serviceVersion: 3.5.15
      replicas: 3
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
```

```bash
kubectl apply -f examples/etcd/cluster-with-tls.yaml
```

Compared to the default configuration, the only difference here is the `tls` and `issuer` fields in the `cluster-with-tls.yaml` file.

```yaml
tls: true  # enable tls
issuer:    # set issuer, could be 'KubeBlocks' or 'UserProvided'
  name: KubeBlocks
```

By default, the `issuer` is set to `KubeBlocks`, which means KubeBlocks will generate the certificates for you and store it in a secret, `<clusterName>-<componentName>-tls-certs`.
If you want to use your own certificates, you can set the `issuer` to `UserProvided` and provide the certificates in the `secretRef` field.

Certifications are mounted to path '/etc/pki/tls' by default. To check how secrets will be mounted, you may check the TLS field in `ComponentDefinition`:

```bash
kubectl get cmpd <cmpdName> -oyaml | yq '.spec.tls'
```

<details>
<summary>Expected Output</summary>

```bash
caFile: ca.pem
certFile: cert.pem
keyFile: key.pem
mountPath: /etc/pki/tls
volumeName: tls
```

</details>

Here is a simple test to verify if TLS works.

- login a read/write ETCD pod (with role=leader)

```bash
kubectl get po  -n demo -l kubeblocks.io/role=leader,apps.kubeblocks.io/component-name=etcd
kubectl exec -n demo -it <podName> -- /bin/bash
```

- put values

```bash
etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/pki/tls/ca.pem \
  --cert=/etc/pki/tls/cert.pem \
  --key=/etc/pki/tls/key.pem \
  put foo bar
```

- get values

```bash
etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/pki/tls/ca.pem \
  --cert=/etc/pki/tls/cert.pem \
  --key=/etc/pki/tls/key.pem \
  get foo
```

<details>
<summary>Expected Output</summary>

```bash
foo
bar
```

</details>

### Horizontal scaling

#### Scale-out

Horizontal scaling out ETCD cluster by adding ONE more replica:

```yaml
# cat examples/etcd/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: etcd-scale-out
  namespace: default 
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: etcd-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: etcd
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/etcd/scale-out.yaml
```

After applying the operation, you will see a new pod created and the cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `follower`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe ops -n demo etcd-scale-out
```

#### Scale-in

Horizontal scaling in etcd cluster by deleting ONE replica:

```yaml
# cat examples/etcd/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: etcd-scale-in
  namespace: default 
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: etcd-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: etcd
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/etcd/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: etcd
      replicas: 3 # Update `replicas` to 1 for scaling in, and to 3 for scaling out
```

### Vertical scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```yaml
# cat examples/etcd/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: etcd-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: etcd-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: etcd
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/etcd/verticalscale.yaml
```

You will observe that the `follower` pod is recreated first, followed by the `leader` pod, to ensure the availability of the cluster.

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: etcd
      replicas: 3
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
# cat examples/etcd/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: etcd-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: etcd-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: etcd
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/etcd/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=etcd-cluster -n demo
```

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: etcd
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

Restart the specified components in the cluster, and instances will be recreated on after another to ensure the availability of the cluster

```yaml
# cat examples/etcd/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: etcd-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: etcd-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: etcd

```

```bash
kubectl apply -f examples/etcd/restart.yaml
```

### Stop

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```yaml
# cat examples/etcd/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: etcd-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: etcd-cluster
  type: Stop

```

```bash
kubectl apply -f examples/etcd/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: etcd
      stop: true  # set stop `true` to stop the component
      replicas: 2
```

### Start

Start the stopped cluster

```yaml
# cat examples/etcd/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: etcd-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: etcd-cluster
  type: Start

```

```bash
kubectl apply -f examples/etcd/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: etcd
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 2
```

### Switchover(switchover.yaml)

A switchover in database clusters is a planned operation that transfers the primary (leader) role from one database instance to another. The goal of a switchover is to ensure that the database cluster remains available and operational during the transition.

To perform a switchover, you can apply the following yaml file:

```yaml
# cat examples/etcd/switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: etcd-switchover
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: etcd-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: etcd
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: etcd-cluster-etcd-3
    candidateName: etcd-cluster-etcd-2
```

```bash
kubectl apply -f examples/etcd/switchover.yaml
```

### Backup

You may find the list of supported Backup Methods:

```bash
# etcd-cluster-etcd-backup-policy is the backup policy name
kubectl get bp -n demo etcd-cluster-etcd-backup-policy -oyaml | yq '.spec.backupMethods[].name'
```

The method `datafile` uses `etcdctl snapshot save` to do a full backup. You may create a backup using:

```yaml
# cat examples/etcd/backup.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: etcd-cluster-backup
  namespace: demo
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - datafile
  backupMethod: datafile
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: etcd-cluster-etcd-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete
```

```bash
kubectl apply -f examples/etcd/backup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -n demo -l app.kubernetes.io/instance=etcd-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

### Restore

To restore a new cluster from a Backup:

```yaml
# cat examples/etcd/restore.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: etcd-cluster-restore
  namespace: demo
  annotations:
    # etcd-cluster-backup is the backup name.
    kubeblocks.io/restore-from-backup: '{"etcd":{"name":"etcd-cluster-backup","namespace":"demo","volumeRestorePolicy":"Parallel"}}'
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: etcd
      componentDef: etcd
      serviceVersion: 3.5.15
      disableExporter: false
      replicas: 3
      resources:
        limits:
          cpu: "0.5"
          memory: "0.5Gi"
        requests:
          cpu: "0.5"
          memory: "0.5Gi"
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
```

```bash
kubectl apply -f examples/etcd/restore.yaml
```

### Observability

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

##### Step 1. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/etcd/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: etcd-cluster-pod-monitor
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
      port: client
      scheme: http
  namespaceSelector:
    matchNames:
      - demo
  selector:
    matchLabels:
      app.kubernetes.io/instance: etcd-cluster
      apps.kubeblocks.io/component-name: etcd
```

```bash
kubectl apply -f examples/etcd/pod-monitor.yaml
```

It sets path to `/metrics` and port to `client` (for container port `2379`).

```yaml
  - path: /metrics
    port: client
    scheme: http
```

##### Step 2. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard, e.g. using etcd dashboard from [Grafana](https://grafana.com/grafana/dashboards).

> [!NOTE]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo etcd-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo etcd-cluster
```
