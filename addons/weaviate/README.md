# Weaviate

Weaviate is an open-source vector database. It allows you to store data objects and vector embeddings from your favorite ML-models, and scale seamlessly into billions of data objects.

In Weaviate, metadata replication and data replication are separate. For the metadata, Weaviate uses the **Raft consensus** algorithm. For data replication, Weaviate uses a **leaderless** design with eventual consistency[^1].

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| No                     | Yes                   | Yes              | Yes       | Yes        | Yes       | Yes    | N/A      |

### Versions

| Versions |
|----------|
| 1.19.6 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Weaviate Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

Create a weaviate cluster with three replicas:

```yaml
# cat examples/weaviate/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: weaviate-cluster
  namespace: demo
spec:
  # Specifies the behavior when a Cluster is deleted.
  # Valid options are: [DoNotTerminate, Delete, WipeOut] (`Halt` is deprecated since KB 0.9)
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  componentSpecs:
    - name: weaviate
      componentDef: weaviate
      replicas: 3
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
                # Set the storage size as needed
                storage: 20Gi

```

```bash
kubectl apply -f examples/weaviate/cluster.yaml
```

### Create with a custom configuration file

Starting with KubeBlocks 1.0, Weaviate configuration is managed through the
`Cluster.spec.componentSpecs[].configs` Configuration API. The previous
`ParametersDefinition` and `ParamConfigRenderer` resources are no longer used.

The example supplies a complete `conf.yaml` template through a ConfigMap and
sets `query_defaults.limit` to `100` when the cluster is created:

Replace `<your-weaviate-component-definition>` in the example with the
ComponentDefinition installed for the Weaviate version you want to run.

```yaml
# cat examples/weaviate/cluster-with-config-template.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-weaviate-config-template
  namespace: demo
data:
  conf.yaml: |-
    ---
    authentication:
      anonymous_access:
        enabled: true
    authorization:
      admin_list:
        enabled: false
    query_defaults:
      limit: {{ .query_defaults_limit }}
    debug: false
---
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: weaviate-cluster-with-config
  namespace: demo
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: weaviate
      componentDef: weaviate
      serviceVersion: 1.19.6
      replicas: 1
      configs:
        # The name must match ComponentDefinition.spec.configs[].name.
        - name: weaviate-config-template
          configMap:
            name: custom-weaviate-config-template
          variables:
            query_defaults_limit: "100"
      resources:
        limits:
          cpu: "1"
          memory: 1Gi
        requests:
          cpu: "0.5"
          memory: 512Mi
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi

```

```bash
kubectl apply -f examples/weaviate/cluster-with-config-template.yaml
```

The config name `weaviate-config-template` must match the corresponding entry
in `ComponentDefinition.spec.configs`. The ConfigMap contains the file template,
while `variables` contains the values rendered into that template.

#### Discover available configurations

Configuration does not provide the parameter schema or value discovery that
was previously supplied by `ParametersDefinition` and `ParamConfigRenderer`.
Use the following sources to determine what can be configured.

List the configuration files exposed by the Weaviate ComponentDefinition:

```bash
WEAVIATE_COMPONENT_DEFINITION="<your-weaviate-component-definition>"
kubectl get cmpd "${WEAVIATE_COMPONENT_DEFINITION}" \
  -o jsonpath='{range .spec.configs[*]}{.name}{"\t"}{.template}{"\t"}{.namespace}{"\n"}{end}'
```

Inspect the default file templates:

```bash
kubectl get configmap weaviate-config-template -n kb-system \
  -o go-template='{{ index .data "conf.yaml" }}'

kubectl get configmap weaviate-env-config-template -n kb-system \
  -o go-template='{{ index .data "envs" }}'
```

For a custom ConfigMap, the placeholders in the file template define the
variable names accepted under `configs[].variables`. For example,
`{{ .query_defaults_limit }}` in this example defines the
`query_defaults_limit` variable. KubeBlocks renders the supplied string value
but does not validate its type or allowed range.

Refer to the [Weaviate environment variable reference][weaviate-env-vars] for
the engine settings, value formats, and defaults. Check that each setting is
supported by Weaviate 1.19.6 because the latest documentation also describes
settings introduced by newer releases.

Inspect the files actually consumed by a running Pod to confirm the effective
rendered values:

```bash
kubectl exec -n demo weaviate-cluster-with-config-weaviate-0 \
  -- cat /weaviate-config/conf.yaml

kubectl exec -n demo weaviate-cluster-with-config-weaviate-0 \
  -- cat /weaviate-env/envs
```

### Update the custom configuration

Update the Configuration variable directly on the Cluster:

```bash
kubectl patch cluster weaviate-cluster-with-config -n demo \
  --type=json \
  --patch-file=examples/weaviate/configure.json
```

This changes `query_defaults.limit` from `100` to `150`. Weaviate 1.19.6 loads
this file at startup, so KubeBlocks restarts the component Pods after rendering
the changed file. This workflow does not create a Reconfiguring OpsRequest.

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/weaviate/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: weaviate-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: weaviate-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: weaviate
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/weaviate/verticalscale.yaml
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
# cat examples/weaviate/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: weaviate-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: weaviate-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: weaviate
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/weaviate/volumeexpand.yaml
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/weaviate/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: weaviate-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: weaviate-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: weaviate

```

```bash
kubectl apply -f examples/weaviate/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/weaviate/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: weaviate-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: weaviate-cluster
  type: Stop

```

```bash
kubectl apply -f examples/weaviate/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/weaviate/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: weaviate-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: weaviate-cluster
  type: Start

```

```bash
kubectl apply -f examples/weaviate/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo weaviate-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo weaviate-cluster
```

## References

[^1]: Weaviate Cluster Architecture, <https://weaviate.io/developers/weaviate/concepts/replication-architecture/cluster-architecture#metadata-replication-raft>

[weaviate-env-vars]: https://docs.weaviate.io/deploy/configuration/env-vars
