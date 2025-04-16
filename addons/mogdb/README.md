# MogDB

MogDB is an enhanced enterprise-ready database developed by Yunhe Enmo based on the openGauss open source database

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                | Yes                   | Yes              | Yes       | Yes        | No       | Yes    | Yes      |

### Versions

| Versions |
|----------|
| 5.0.5    |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- MogDB Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

Create a MogDB cluster with specified cluster definition

```yaml
# cat examples/mogdb/cluster.yaml
# Source: mogdb-cluster/templates/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: mogdb-cluster
  namespace: demo
spec:
  # Specifies the behavior when a Cluster is deleted.
  # Valid options are: [DoNotTerminate, Delete, WipeOut] (`Halt` is deprecated since KB 0.9)
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  componentSpecs:
    - name: mogdb
      componentDef: mogdb
      serviceVersion: "5.0.5"
      replicas: 2
      # Specifies the resources required by the Component.
      resources:
        limits:
          cpu: "1"
          memory: "1Gi"
        requests:
          cpu: "1"
          memory: "1Gi"
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
kubectl apply -f examples/mogdb/cluster.yaml
```

To connect to the MogDB cluster, you can use the following command.

1. Login to the MogDB pod

```bash
kubectl exec -it mogdb-cluster-mogdb-0 -c mogdb -- bash
```

2. Connect to the MogDB cluster using the client

```bash
gsql -U$MOGDB_USER -p26000 postgres -W "$MOGDB_PASSWORD"
```

### Horizontal scaling

#### Scale-out

Horizontal scaling out PostgreSQL cluster by adding ONE more replica:

```yaml
# cat examples/mogdb/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mogdb-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mogdb-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: mogdb
    # Specifies the replica changes for scaling out components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/mogdb/scale-out.yaml
```

After applying the operation, you will see a new pod created and the PostgreSQL cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `secondary`.

And you can check the progress of the scaling operation with following command:

#### Scale-in

Horizontal scaling in PostgreSQL cluster by deleting ONE replica:

```yaml
# cat examples/mogdb/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mogdb-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mogdb-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: mogdb
    # Specifies the replica changes for scaling in components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1

```

```bash
kubectl apply -f examples/mogdb/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mogdb
      replicas: 2 # Update `replicas` to 1 for scaling in, and to 3 for scaling out
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/mogdb/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mogdb-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mogdb-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: mogdb
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1.5Gi
    limits:
      cpu: '1'
      memory: 1.5Gi

```

```bash
kubectl apply -f examples/mogdb/verticalscale.yaml
```

### Expand volume

Increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/mogdb/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mogdb-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mogdb-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: mogdb
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/mogdb/volumeexpand.yaml
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/mogdb/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mogdb-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mogdb-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: mogdb

```

```bash
kubectl apply -f examples/mogdb/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/mogdb/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mogdb-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mogdb-cluster
  type: Stop

```

```bash
kubectl apply -f examples/mogdb/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/mogdb/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mogdb-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mogdb-cluster
  type: Start

```

```bash
kubectl apply -f examples/mogdb/start.yaml
```

### Switchover

Switchover a non-primary or non-leader instance as the new primary or leader of the cluster

```yaml
# cat examples/mogdb/switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mogdb-cluster-switchover
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mogdb-cluster
  type: Custom
  custom:
    # Specifies the name of the OpsDefinition, it is a custom-defined ops to perform switch-over for mogdb
    opsDefinitionName: mogdb-switchover
    components:
      - componentName: mogdb
        parameters:
          - name: candidate
            value: mogdb-cluster-mogdb-1
```

```bash
kubectl apply -f examples/mogdb/switchover.yaml
```

MogDB defines the switchover operation in the `mogdb-switchover` OpsDefinition. It will be run as a Job and its main steps are:

1. Execute switchover command
   - Uses gs_ctl switchover on candidate pod
   - Runs as 'omm' user

2. Verification loop (60s timeout)
   - If candidate specified:
     - Checks only candidate pod role
   - If no candidate:
     - Checks all pods except old primary
     - Looks for Primary/Leader/Master role

3. Success criteria:
   - New pod has role: Primary/primary/leader/master
   - Exits with 0 on success, 1 on failure

### Reconfigure

Configure parameters with the specified components in the cluster

```yaml
# cat examples/mogdb/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: mogdb-reconfiguring
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: mogdb-cluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: mogdb
    # Defines a list of key-value pairs for a single configuration file.
    # These parameters are used to update the specified configuration settings.
    parameters:
      # Represents the name of the parameter that is to be updated.
    - key: shared_buffers
      # Represents the parameter values that are to be updated.
      # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
      value: 512MB
    - key: max_connections
      value: '200'
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring

```

```bash
kubectl apply -f examples/mogdb/configure.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo mogdb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

 kubectl delete cluster -n demomogdb-cluster
```
