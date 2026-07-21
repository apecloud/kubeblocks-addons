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

### [Create](cluster.yaml)

Create a weaviate cluster with three replicas:

```bash
kubectl apply -f examples/weaviate/cluster.yaml
```

### [Create with a custom configuration file](cluster-with-config-template.yaml)

Starting with KubeBlocks 1.0, Weaviate configuration is managed through the
`Cluster.spec.componentSpecs[].configs` Configuration API. The previous
`ParametersDefinition` and `ParamConfigRenderer` resources are no longer used.

The example supplies a complete `conf.yaml` template through a ConfigMap and
sets `query_defaults.limit` to `100` when the cluster is created:

Replace `<your-weaviate-component-definition>` in the example with the
ComponentDefinition installed for the Weaviate version you want to run.

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

### [Update the custom configuration](configure.json)

Update the Configuration variable directly on the Cluster:

```bash
kubectl patch cluster weaviate-cluster-with-config -n demo \
  --type=json \
  --patch-file=examples/weaviate/configure.json
```

This changes `query_defaults.limit` from `100` to `150`. Weaviate 1.19.6 loads
this file at startup, so KubeBlocks restarts the component Pods after rendering
the changed file. This workflow does not create a Reconfiguring OpsRequest.

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/weaviate/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created. It is introduced in Kubernetes v1.11 and goes GA in Kubernetes v1.24. It allows Kubernetes users to simply edit their PersistentVolumeClaim objects  without requiring any downtime at all if possible.

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

To increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/weaviate/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/weaviate/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/weaviate/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

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
