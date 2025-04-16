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

### [Create](cluster.yaml)

Create a MogDB cluster with specified cluster definition

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

#### [Scale-out](scale-out.yaml)

Horizontal scaling out PostgreSQL cluster by adding ONE more replica:

```bash
kubectl apply -f examples/mogdb/scale-out.yaml
```

After applying the operation, you will see a new pod created and the PostgreSQL cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `secondary`.

And you can check the progress of the scaling operation with following command:

#### [Scale-in](scale-in.yaml)

Horizontal scaling in PostgreSQL cluster by deleting ONE replica:

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

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/mogdb/verticalscale.yaml
```

### [Expand volume](volumeexpand.yaml)

Increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/mogdb/volumeexpand.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/mogdb/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/mogdb/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/mogdb/start.yaml
```

### [Switchover](switchover.yaml)

Switchover a non-primary or non-leader instance as the new primary or leader of the cluster

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

### [Reconfigure](configure.yaml)

Configure parameters with the specified components in the cluster

```bash
kubectl apply -f examples/mogdb/configure.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo mogdb-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

 kubectl delete cluster -n demomogdb-cluster
```
