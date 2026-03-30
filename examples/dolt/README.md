# Dolt

[Dolt](https://github.com/dolthub/dolt) is a MySQL-compatible SQL database with Git-style versioning. This addon runs `dolt sql-server` in replication (primary / standby) or standalone mode.

## Prerequisites

- Kubernetes >= v1.21
- KubeBlocks installed
- Dolt addon installed from `addons/dolt` (installs ComponentDefinitions `dolt-replication` and `dolt-standalone`)
- Namespace `demo` (or change `metadata.namespace` in the manifests):

  ```bash
  kubectl create ns demo
  ```

## Install addon

```bash
helm install dolt ./addons/dolt -n kb-system
```

Adjust `kb-system` to the namespace where your KubeBlocks addons are installed.

## Examples

### Create a primary / standby cluster

[`cluster-replication.yaml`](cluster-replication.yaml) creates a two-replica Dolt replication cluster (Dolt primary + standby).

```bash
kubectl apply -f examples/dolt/cluster-replication.yaml
```

Check supported versions:

```bash
kubectl get cmpv dolt
```

Match `spec.componentSpecs[].componentDef` to the addon (`dolt-replication` or `dolt-standalone`), and `serviceVersion` to a release in that ComponentVersion (for example `1.84.0`).

### Switchover

After the cluster is healthy, trigger a planned switchover so another replica becomes primary.

**With explicit candidate** — [`switchover-specified-instance.yaml`](switchover-specified-instance.yaml):

```bash
kubectl apply -f examples/dolt/switchover-specified-instance.yaml
```

Edit `instanceName` / `candidateName` to match your pod names (`<clusterName>-dolt-<ordinal>`). Get pods:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=dolt-repl -L kubeblocks.io/role
```

### Create a single-node (standalone) cluster

[`cluster-standalone.yaml`](cluster-standalone.yaml) uses the standalone ComponentDefinition (exactly one replica).

```bash
kubectl apply -f examples/dolt/cluster-standalone.yaml
```

Switchover does not apply to standalone topology (single replica).
