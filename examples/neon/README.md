# Neon

Neon is a serverless open-source alternative to AWS Aurora Postgres. It separates storage and compute and substitutes the PostgreSQL storage layer by redistributing data across a cluster of nodes.

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- Neon Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

Create a neon cluster with specified cluster definition.

```bash
kubectl apply -f examples/neon/cluster.yaml
```

### Vertical scaling NeonVM

Vertical scaling up or down NeonVM specified cpu or memory.

View NeonVM CPU/MEMORY information.

```bash
kubectl get neonvm -n demo
NAME              CPUS   MEMORY   POD                     EXTRAIP   STATUS    AGE
vm-compute-node   1      1Gi      vm-compute-node-g8wsb             Running   5m22s
```

Vertical scaling NeonVM CPU

```bash

kubectl patch neonvm -n demo vm-compute-node --type='json' -p='[{"op": "replace", "path": "/spec/guest/cpus/use", "value":2}]'
```

View NeonVM CPU information after Vertical scaling.

```bash
kubectl get neonvm -n demo
NAME              CPUS   MEMORY   POD                     EXTRAIP   STATUS    AGE
vm-compute-node   2      1Gi      vm-compute-node-g8wsb             Running   5m45s
```

Vertical scaling NeonVM MEMORY

```bash
kubectl patch neonvm vm-compute-node --type='json' -p='[{"op": "replace", "path": "/spec/guest/memorySlots/use", "value":4}]'
```

View NeonVM MEMORY information after Vertical scaling.

```bash
kubectl get neonvm -n demo
NAME              CPUS   MEMORY   POD                     EXTRAIP   STATUS    AGE
vm-compute-node   2      4Gi      vm-compute-node-g8wsb             Running   10m
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo neon-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo neon-cluster
```
