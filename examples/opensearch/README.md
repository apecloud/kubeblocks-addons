# OpenSearch

OpenSearch is a scalable, flexible, and extensible open-source software suite for search, analytics, and observability applications licensed under Apache 2.0.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | Yes               | Yes       | Yes        | No        | Yes    | No      |

### Versions

| Versions |
|----------|
| 2.7.0 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- OpenSearch Addon Enabled, refer to [Install Addons](../docs/install-addon.md)

## Examples

### [Create](cluster.yaml)

Create a opensearch cluster with three replicas:

```bash
kubectl apply -f examples/opensearch/cluster.yaml
```

To access the OpenSearch cluster, you can use the following command to get the service URL:

```bash
kubectl port-forward svc/opensearch-cluster-opensearch 9200:9200
```

Then you can check the cluster status with the following command:

```bash
curl -u admin:admin -X GET https:/127.0.0.1:9200/_cluster/health?pretty --insecure
```

Ensure the `status` field is `green` before proceeding with the next steps.

To check the roles of nodes in the cluster, you can use the following command:

```bash
curl -u admin:admin -X GET https:/127.0.0.1:9200/_nodes?pretty --insecure
```

For more information of OpenSearch APIs, please refer to [OpenSearch APIs](https://opensearch.org/docs/latest/api-reference/cluster-api/index/)

To access OpenSearch Dashboard, you can use the following command to get the service URL:

```bash
kubectl port-forward svc/opensearch-cluster-dashboard 5601:5601
```

Then you can access the OpenSearch Dashboard with the following URL:

```bash
http://localhost:5601/app/home#/
```

And you can login with the default username and password:

```text
username: admin
password: admin
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out cluster by adding ONE more `OpenSearch` replica:

```bash
kubectl apply -f examples/opensearch/scale-out.yaml
```

And you can check the progress of the scaling operation with following command:

#### [Scale-in](scale-in.yaml)

Horizontal scaling in cluster by deleting ONE replica:

```bash
kubectl apply -f examples/opensearch/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: opensearch-cluster
  namespace: default
spec:
  terminationPolicy: Delete
  componentSpecs:
    - name: opensearch
      componentDef: opensearch-1.0.0
      serviceVersion: "2.7.0"
      replicas: 3 # update replicas to your need (but not zero)
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/opensearch/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/opensearch/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/opensearch/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/opensearch/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/opensearch/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster opensearch-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster opensearch-cluster
```
