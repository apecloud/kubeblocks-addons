# Influxdb

InfluxDB enables real-time analytics by serving as a purpose-built database that optimizes processing and scaling for large time series data workloads.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| No                     | Yes                   | Yes               | Yes       | Yes        | Yes       | Yes    | No      |

### Versions

| Versions |
|----------|
| 2.7.11   |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- InfluxDB Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

Create a influxdb cluster with specified cluster definition

```yaml
# cat examples/influxdb/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: influxdb-cluster
  namespace: demo
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: influxdb
      componentDef: influxdb
      serviceVersion: 2.7.11
      replicas: 1
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
kubectl apply -f examples/influxdb/cluster.yaml
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/influxdb/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: influxdb-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: influxdb-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
  - componentName: influxdb
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: 1Gi
    limits:
      cpu: '1'
      memory: 1Gi

```

```bash
kubectl apply -f examples/influxdb/verticalscale.yaml
```

### Expand volume

Increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/influxdb/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: influxdb-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: influxdb-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
  - componentName: influxdb
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/influxdb/volumeexpand.yaml
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/influxdb/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: influxdb-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: influxdb-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
  - componentName: influxdb

```

```bash
kubectl apply -f examples/influxdb/restart.yaml
```

### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/influxdb/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: influxdb-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: influxdb-cluster
  type: Stop

```

```bash
kubectl apply -f examples/influxdb/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/influxdb/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: influxdb-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: influxdb-cluster
  type: Start

```

```bash
kubectl apply -f examples/influxdb/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo influxdb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo influxdb-cluster
```

## System account password compatibility

Chart `1.2.0-alpha.1` targets KubeBlocks 1.2 and later and renders
`spec.systemAccounts[].passwordConfig`. It preserves the existing account names,
initialization flags, provisioning statements, password policies and credential
references. The chart version bump creates new ComponentDefinition names rather
than changing the immutable account structure of an existing definition.
ComponentVersion selectors continue to match the previous and new definitions.

This is not an automatic migration or password rotation for existing clusters.
Keep the definitions and Secrets referenced by existing Components; a chart update
does not repair empty or invalid credentials created before this change. Verify
that the installed operator and CRDs support the declared product line before use.
The support annotation does not perform an online CRD check or promise support
for KubeBlocks 1.0/1.1.

Default `extra.keepResource: true` retains definitions during chart changes.
Installations that disable retention must arrange preservation of definitions
still used by existing Components before upgrading.

Offline regression checks render installation and upgrade manifests, cover custom
registry/namespace and a later chart version, and verify every account policy,
credential consumer, definition retention and old/new version selection:

```bash
helm dependency build addons/influxdb
helm lint addons/influxdb
shellspec --load-path shellspec addons/influxdb/scripts-ut-spec/password_config_spec.sh
```


The fixed-name ParametersDefinitions continue to select both the retained
`1.2.0-alpha.0` definitions and this chart's definitions. Their file and template
mappings are unchanged, so retaining an old ComponentDefinition does not remove
its parameter mapping. These selectors intentionally cover only those two
definition identities; subsequent chart releases must preserve any additional
identities that are still in use.

InfluxDB also continues to render `influxdb-scripts-1.2.0-alpha.0` with its
unchanged scripts. The old source remains in Helm's desired manifest even though
the previous release had no retention annotation. Both old and new script
sources now respect `extra.keepResource`; neither existing data/meta Components
nor their source-template references are rewritten by this migration.
