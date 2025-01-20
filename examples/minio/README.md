# Minio

Minio is a high performance open source relational database management system that is widely used for web and application servers

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | No                | Yes       | Yes        | No        | Yes    | N/A       |

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

## Examples

### [Create](cluster.yaml)

Create a minio cluster with specified cluster definition
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
kubectl get secret minio-cluster-minio-account-root -o jsonpath="{.data.password}" | base64 --decode
kubectl get secret minio-cluster-minio-account-root -o jsonpath="{.data.username}" | base64 --decode
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster
```bash
kubectl apply -f examples/minio/verticalscale.yaml
```


### [Restart](restart.yaml)

Restart the specified components in the cluster
```bash
kubectl apply -f examples/minio/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved
```bash
kubectl apply -f examples/minio/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster
```bash
kubectl apply -f examples/minio/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster
```bash
kubectl patch cluster minio-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster minio-cluster
```
