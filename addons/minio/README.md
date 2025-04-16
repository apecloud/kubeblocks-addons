# Minio

Minio is a high performance open source relational database management system that is widely used for web and application servers

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Scale Out              | Yes                   | No                | Yes       | Yes        | No        | Yes    | N/A       |

### Versions

| Versions |
|----------|
| 2024-06-29T01-20-47Z |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Minio Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

Create a minio cluster with two replicas:

```yaml
# cat examples/minio/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: minio-cluster
  namespace: demo
spec:
  # Specifies the behavior when a Cluster is deleted.
  # Valid options are: [DoNotTerminate, Delete, WipeOut] (`Halt` is deprecated since KB 0.9)
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  componentSpecs:
    - componentDef: minio
      name: minio
      # for dev/test, set replicas to 2
      # for prod , MinIO clusters must be configured with at least 4 replicas
      # and the number of nodes must also be a multiple of 2 (e.g., 4, 6, 8, 12, etc.)
      # to maintain balanced erasure coding.
      replicas: 2
      # following is an simple example of schedulingPolicy
      # which requires pods from the same component `minio` cannot be scheduled to the same node
      # --- start of example
      # schedulingPolicy:
      #   affinity:
      #     podAntiAffinity:
      #       preferredDuringSchedulingIgnoredDuringExecution:
      #         - podAffinityTerm:
      #             labelSelector:
      #               matchLabels:
      #                 app.kubernetes.io/instance: minio-cluster
      #                 apps.kubeblocks.io/component-name: minio
      #             topologyKey: kubernetes.io/hostname
      #           weight: 100
      #       requiredDuringSchedulingIgnoredDuringExecution:
      #         - labelSelector:
      #             matchLabels:
      #               app.kubernetes.io/instance: minio-cluster
      #               apps.kubeblocks.io/component-name: minio
      #           topologyKey: kubernetes.io/hostname
      # --- end of example
      env:
        # MINIO_BUCKETS is a comma-separated list of bucket names that will be automatically
        # created during MinIO initialization. Example: "data,backup,logs"
        - name: MINIO_BUCKETS
          value:
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
kubectl apply -f examples/minio/cluster.yaml
```

To visit the dashboard of minio, you can use the following command.

1. poforward the frontend service to access the minio cluster

```bash
kubectl port-forward svc/minio-cluster-frontend 9001:9001
```

2. Visit the dashboard of minio

```bash
open http://localhost:9001
```

3. Login the dashboard of minio

Credentials can be found in the secret `minio-cluster-minio-account-root` in the namespace where the minio cluster is deployed.

```bash
kubectl get secret -n demo minio-cluster-minio-account-root -o jsonpath="{.data.password}" | base64 --decode
kubectl get secret -n demo minio-cluster-minio-account-root -o jsonpath="{.data.username}" | base64 --decode
```

### Horizontal scaling

#### Scale-out

Horizontal scaling out MinIO cluster by adding TWO more replica:

> [!Note]
> MinIO clusters must be configured with at least 2 replicas
> And the number of replicas must also be a multiple of 2 (e.g., 4, 6, 8, 12, etc.) to maintain balanced erasure coding.

```yaml
# cat examples/minio/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: minio-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: minio-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: minio
    # Specifies the replica changes for scaling in components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 2
```

```bash
kubectl apply -f examples/minio/scale-out.yaml
```

After scaling out, two newly created replicas are running with empty roles (expected role is `readwrite`).
When checking the logs of the new replicas, for example, minio-cluster-minio-2:

```bash
kubectl logs minio-cluster-minio-2 -c minio
```

You will see the following log:

```bash
Error: grid: http://minio-cluster-minio-2.minio-cluster-minio-headless.default.svc.cluster.local:9000 re-connecting to ws://minio-cluster-minio-0.minio-cluster-minio-headless.default.svc.cluster.local:9000/minio/grid/v1: connection rejected: unknown incoming host: http://minio-cluster-minio-2.minio-cluster-minio-headless.default.svc.cluster.local:9000 (*errors.errorString) Sleeping 1.119s (3) (*fmt.wrapError)
```

#### Option1: Force a STOP-START to make sure the new replicas are running correctly

Then you must force a RESTART to make sure the new replicas are running correctly.

1. Force a STOP request to stop the cluster

```bash
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: minio-force-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: minio-cluster
  force: true # to force restart the minio-cluster even the cluster is Updating
  type: Stop
```

When the cluster is stopped, the new replicas will be stopped correctly and the scale-out OpsRequest `minio-scale-out`  goes `aborted`.

2. Force a START request to start the cluster

```bash
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: minio-force-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: minio-cluster
  force: true # to force restart the minio-cluster even the cluster is Updating
  type: Start
```

After STOP-START, the new replicas will be running correctly.

#### Option 2: Restart Existing replicas only

If you don't want to force a STOP-START, you can restart the existing replicas only.

```bash
kubectl delete pod -n demo minio-cluster-minio-{0..1}
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/minio/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: minio-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: minio-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: minio
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/minio/verticalscale.yaml
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/minio/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: minio-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: minio-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: minio
```

```bash
kubectl apply -f examples/minio/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/minio/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: minio-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: minio-cluster
  force: true
  type: Stop

```

```bash
kubectl apply -f examples/minio/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/minio/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: minio-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: minio-cluster
  type: Start

```

```bash
kubectl apply -f examples/minio/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo minio-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

 kubectl delete cluster -n demominio-cluster
```
