# PolarDB-X

PolarDB-X is a cloud native distributed SQL Database designed for high concurrency, massive storage, complex querying scenarios.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes (cn, cdc)          | Yes                   | Yes              | Yes       | Yes        | No       | Yes    | No      |

### Versions

| Versions |
|----------|
| 2.3.0 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- PolarDB-X Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### Create

> [!IMPORTANT]
> Make sure the `clusterName` and `namespace` are short such that the length of following string is less than 64 characters
>
> - `<clusterName>`-gms-`<id>`.`<clusterName>`-gms-headless.`<namesapce>`.svc.cluster.local:11306
>
> This is a constraint of the PolarDB-X database. The column `IP_PORT` defined in table `information_schema.ALISQL_CLUSTER_GLOBAL` is of type `VARCHAR(64)`.
> You may login to the database and run the following SQL to check the definition of the table:
>
> ```sql
> show create table information_schema.ALISQL_CLUSTER_GLOBAL;
> ```

Create a polardbx cluster with four components: cn, dn, cdc, and gms.

```yaml
# cat examples/polardbx/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: pxc
  namespace: default
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: gms
      componentDef: polardbx-gms
      replicas: 1
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
        requests:
          cpu: "1"
          memory: "1Gi"
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
    - name: dn-0
      componentDef: polardbx-dn
      replicas: 1
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
        requests:
          cpu: "1"
          memory: "1Gi"
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: ""
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
    - name: cn
      componentDef: polardbx-cn
      replicas: 2
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
        requests:
          cpu: "1"
          memory: "1Gi"
    - name: cdc
      componentDef: polardbx-cdc
      replicas: 1
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
```

```bash
kubectl apply -f examples/polardbx/cluster.yaml
```

As PolarDB-X is a distributed database with multiple components. You may prefer to distribute replicas to different nodes to avoid single point of failure. Here is an example of how to distribute replicas to different nodes using `schedulingPolicy` API:

```yaml
kubectl apply -f examples/polardbx/cluster-with-schedule-policy.yaml
```

To connect to the database, you can use the following command to get the connection information:

```bash
kubectl port-forward svc/pxc-cn 3306:3306
mysql -h127.0.0.1 -u$USER_NAME -p$PASSWORD
```

Credentials can be found in the secret `pxc-gms-account-polardbx-root` in the namespace where the cluster is deployed.

```bash
kubectl get secret pxc-gms-account-polardbx-root -o jsonpath="{.data.password}" | base64 --decode
kubectl get secret pxc-gms-account-polardbx-root -o jsonpath="{.data.username}" | base64 --decode
```

### Horizontal scaling

#### Scale-out

Horizontal scaling out polardbx cluster by adding ONE more `cn` replica:

```yaml
# cat examples/polardbx/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: polardbx-scale-out-cn
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pxc
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - cn
    # - cdc
  - componentName: cn
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/polardbx/scale-out.yaml
```

#### Scale-in

Horizontal scaling in polardbx cluster by deleting ONE `cn` replica:

```yaml
# cat examples/polardbx/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: polardbx-scale-in-cn
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pxc
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
    # - cn
    # - cdc
  - componentName: cn
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/polardbx/scale-in.yaml
```

### Vertical scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```yaml
# cat examples/polardbx/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: polardbx-verticalscaling
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pxc
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
    # - cn
    # - cdc
  - componentName: cn
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: '2Gi'
    limits:
      cpu: '1'
      memory: '2Gi'

```

```bash
kubectl apply -f examples/polardbx/verticalscale.yaml
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
# cat examples/polardbx/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: polardbx-volumeexpansion
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pxc
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
    # - gms
    # - dn
  - componentName: dn
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
      # A reference to the volumeClaimTemplate name from the cluster components.
      # - datanode, datanode
      # - etcd, etcd-storage
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/polardbx/volumeexpand.yaml
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/polardbx/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: polardbx-restart
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pxc
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
    # - cn
    # - cdc
  - componentName: cn

```

```bash
kubectl apply -f examples/polardbx/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/polardbx/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: polardbx-stop
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pxc
  type: Stop

```

```bash
kubectl apply -f examples/polardbx/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/polardbx/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: polardbx-start
  namespace: default
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: pxc
  type: Start

```

```bash
kubectl apply -f examples/polardbx/start.yaml
```

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/polardbx/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: pxc-pod-monitor
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
  - kubeblocks.io/role
  podMetricsEndpoints:
    - path: /metrics
      port: metrics
      scheme: http
  namespaceSelector:
    matchNames:
      - default
  selector:
    matchLabels:
      app.kubernetes.io/instance: pxc
```

```bash
kubectl apply -f examples/polardbx/pod-monitor.yaml
```

##### Access the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard [PolarDB-X Dashboard Overview](https://github.com/apecloud/kubeblocks-addons/blob/main/addons/polardbx/dashboards/polardbx-overview.json) to monitor the cluster.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster pxc -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster pxc
```
