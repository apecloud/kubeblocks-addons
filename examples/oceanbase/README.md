# OceanBase

OceanBase Database is an enterprise-level native distributed database independently developed by Ant Group.[^2]

## OceanBase Features In KubeBlocks

### Life-cycle Management

|   Topology       | Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| distribution     | Yes                    | Yes                   | No                | Yes       | Yes        | Yes       | Yes    | N/A      |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Backup [^1] | full   | Backs up all macro-blocks.                |
| Restore     | full   | Restore a new cluster from a full backup. |

### Versions

| Service Version | Description |
|-----------------|-------------|
| 4.3.0           | OceanBase 4.3.0.1-100000242024032211 |


## Prerequisites

This example assumes that you have a Kubernetes cluster installed and running, and that you have installed the kubectl command line tool and helm somewhere in your path. Please see the [getting started](https://kubernetes.io/docs/setup/)  and [Installing Helm](https://helm.sh/docs/intro/install/) for installation instructions for your platform.

Also, this example requires KubeBlocks installed and running. Here is the steps to install KubeBlocks, please replace "`$kb_version`" with the version you want to use.

```bash
# Add Helm repo
helm repo add kubeblocks https://apecloud.github.io/helm-charts
# If github is not accessible or very slow for you, please use following repo instead
helm repo add kubeblocks https://jihulab.com/api/v4/projects/85949/packages/helm/stable

# Update helm repo
helm repo update

# Get the versions of KubeBlocks and select the one you want to use
helm search repo kubeblocks/kubeblocks --versions
# If you want to obtain the development versions of KubeBlocks, Please add the '--devel' parameter as the following command
helm search repo kubeblocks/kubeblocks --versions --devel

# Create dependent CRDs
kubectl create -f https://github.com/apecloud/kubeblocks/releases/download/v$kb_version/kubeblocks_crds.yaml
# If github is not accessible or very slow for you, please use following command instead
kubectl create -f https://jihulab.com/api/v4/projects/98723/packages/generic/kubeblocks/v$kb_version/kubeblocks_crds.yaml

# Install KubeBlocks
helm install kubeblocks kubeblocks/kubeblocks --namespace kb-system --create-namespace --version="$kb_version"
```

### Enable OceanBase Add-on


#### Using Helm

```bash
# Add Helm repo
helm repo add kubeblocks-addons https://apecloud.github.io/helm-charts
# If github is not accessible or very slow for you, please use following repo instead
helm repo add kubeblocks-addons https://jihulab.com/api/v4/projects/150246/packages/helm/stable
# Update helm repo
helm repo update
# Search versions of OceanBase
helm search repo kubeblocks/oceanbase-ce --versions
# Install the version you want (replace $version with the one you need)
helm upgrade -i oceanbase-ce kubeblocks-addons/oceanbase-ce --version $version -n kb-system
```

#### Using kbcli

```bash
# Search Addon
kbcli addon search oceanbase-ce
# Install Addon with the version you want, replace $version with the one you need
kbcli addon install oceanbase-ce --version $version
# To upgrade the addon, you can use the following command
kbcli addon upgrade oceanbase-ce --version $version
```

## Examples

### [Create](cluster.yaml)

Create a distributed oceanbase cluster

```bash
kubectl apply -f examples/oceanbase/cluster.yaml
```

Optionally, you can create a cluster using HostNetwork mode, by turning on the feature-gate.
And KubeBlocks will allocate AVAILABLE ports for the components. Details can be found in file [Create HostNetwork](cluster-hostnetwork.yaml).

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: ob-cluster-host
  namespace: default
  annotations:
    # `kubeblocks.io/host-network` is a reserved annotation
    # it defines the feature gate to enable the host-network for specified components or shardings.
    kubeblocks.io/host-network: "oceanbase"
spec:
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out the cluster by adding ONE more replica:

```bash
kubectl apply -f examples/oceanbase/scale-out.yaml
```

After applying the operation, you will see a new pod created and the cluster status goes from `Updating` to `Running`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe ops ob-scale-out -n default
```

The newly added replica will be in `Pending` status, and it will be in `Running` status after the operation is completed. By checking the logs of the POD, you can see the progress of the scaling operation.

```bash
kubectl logs -f <pod-name> -n default
```

And you will see the logs once the new replica is added to the cluster.

```bash
| Wait for the server to be ready...
│ Add the server to zone successfully
│ Cluster starts successfully
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in the cluster by removing ONE replica:

```bash
kubectl apply -f examples/oceanbase/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: ob-cluster
  namespace: default
spec:
  componentSpecs:
    - name: oceanbase
      serviceVersion: "4.3.0"
      disableExporter: false
      replicas: 3 # increase `replicas` for scaling in, and decrease for scaling out
```


### [Vertical scaling](verticalscale.yaml)

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```bash
kubectl apply -f examples/oceanbase/verticalscale.yaml
```

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: ob-cluster
  namespace: default
spec:
  componentSpecs:
    - name: oceanbase
      replicas: 1
      resources:
        requests:
          cpu: "4"       # Update the resources to your need.
          memory: 6Gi"  # Update the resources to your need.
        limits:
          cpu: "4"       # Update the resources to your need.
          memory: "6Gi"  # Update the resources to your need.
```

### [Restart](restart.yaml)

Restart the specified components in the cluster, and instances will be recreated on after another to ensure the availability of the cluster

```bash
kubectl apply -f examples/oceanbase/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```bash
kubectl apply -f examples/oceanbase/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: ob-cluster
  namespace: default
spec:
  componentSpecs:
    - name: oceanbase
      stop: true  # set stop `true` to stop the component
      replicas: 1
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/oceanbase/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: ob-cluster
  namespace: default
spec:
  componentSpecs:
    - name: oceanbase
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 1
```

### [Reconfigure](configure.yaml)

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability. The reconfiguration can be either:

- Dynamic: Applied without restart
- Static: Requires database restart

Reconfigure parameters with the specified components in the cluster

```bash
kubectl apply -f examples/oceanbase/configure.yaml
```

This example will change the `system_memory` to `2Gi`.
> `system_memory` specifies the size of memory reserved by the system tenant. It is a dynamic parameter, so the change will take effect without restarting the database.

```bash
kbcli cluster explain-config pg-cluster # kbcli is a command line tool to interact with KubeBlocks
```

### [BackupRepo](backuprepo.yaml)

BackupRepo is the storage repository for backup data. Before creating a BackupRepo, you need to create a secret to save the access key of the backup repository

```bash
# Create a secret to save the access key
kubectl create secret generic <credential-for-backuprepo>\
  --from-literal=accessKeyId=<ACCESS KEY> \
  --from-literal=secretAccessKey=<SECRET KEY> \
  -n kb-system
```

Update `examples/postgresql/backuprepo.yaml` and set fields quoted with `<>` to your own settings and apply it.

```bash
kubectl apply -f examples/postgresql/backuprepo.yaml
```

After creating the BackupRepo, you should check the status of the BackupRepo, to make sure it is `Ready`.

```bash
kubectl get backuprepo
```

And the expected output is like:

```bash
NAME     STATUS   STORAGEPROVIDER   ACCESSMETHOD   DEFAULT   AGE
kb-oss   Ready    oss               Tool           true      Xd
```

### Backup

### [Backup](backup.yaml)

To create a base backup for the cluster, you can apply the following yaml file:

```bash
kubectl apply -f examples/oceanbase/backup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -l app.kubernetes.io/instance=pg-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

Information, such as `path`, `timeRange` about the backup will be recorded into the `Backup` resource.

Alternatively, you can update the `BackupSchedule` to enable the method `full` to schedule full backup periodically.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
metadata:
  name: ob-cluster-oceanbase-backup-schedule
  namespace: default
spec:
  backupPolicyName: ob-cluster-oceanbase-backup-policy
  schedules:
  - backupMethod: full # backup method name, do not chagne
    # ┌───────────── minute (0-59)
    # │ ┌───────────── hour (0-23)
    # │ │ ┌───────────── day of month (1-31)
    # │ │ │ ┌───────────── month (1-12)
    # │ │ │ │ ┌───────────── day of week (0-6) (Sunday=0)
    # │ │ │ │ │
    # 0 18 * * *
    # schedule this job every day at 6:00 PM (18:00).
    cronExpression: 0 18 * * *  # set the cronExpression to your need
    enabled: false  # set to `true` to enable incremental backup
    retentionPeriod: 7d # set the retention period to your need, default is 7 days
```

### [Restore](restore.yaml)

To restore a new cluster from a `Backup`, you can apply the following yaml file:

1. Get the list of accounts and their passwords from the backup:

```bash
kubectl get backup ob-cluster-backup -ojsonpath='{.metadata.annotations.kubeblocks\.io/encrypted-system-accounts}'
```

1. Update `examples/oceanbase/restore.yaml` and set fields quoted with `<<ENCRYPTED-SYSTEM-ACCOUNTS>` to your own settings and apply it.

```bash
kubectl apply -f examples/oceanbase/restore.yaml
```

### Expose

Expose a cluster with a new endpoint

#### [Enable](expose-enable.yaml)

```bash
kubectl apply -f examples/oceanbase/expose-enable.yaml
```

#### [Disable](expose-disable.yaml)

```bash
kubectl apply -f examples/oceanbase/expose-disable.yaml
```

#### Expose SVC using Cluster API

Alternatively, you may expose service by updating `spec.services`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: ob-cluster
  namespace: default
spec:
  # append service to the list
  services:
    # add annotation for cloud loadbalancer if
    # services.spec.type is LoadBalancer
    # here we use annotation for alibaba cloud for example
  - annotations:
      service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: internet
    componentSelector: oceanbase
    name: oceanbase-vpc
    serviceName: oceanbase-vpc
    spec:  # defines the behavior of a K8s service.
      ipFamilyPolicy: PreferDualStack
      ports:
      - name: sql
        # port to expose
        port: 2881
        protocol: TCP
        targetPort: sql
      # Valid options:[ClusterIP, NodePort, LoadBalancer, ExternalName]
      type: LoadBalancer
```

If the service is of type `LoadBalancer`, please add annotations for cloud loadbalancer depending on the cloud provider you are using. Here list annotations for some cloud providers[^3]:

```yaml
# alibaba cloud
service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: "internet"  # or "intranet"

# aws
service.beta.kubernetes.io/aws-load-balancer-type: nlb  # Use Network Load Balancer
service.beta.kubernetes.io/aws-load-balancer-internal: "true"  # or "false" for internet

# azure
service.beta.kubernetes.io/azure-load-balancer-internal: "true" # or "false" for internet

# gcp
networking.gke.io/load-balancer-type: "Internal" # for internal access
cloud.google.com/l4-rbs: "enabled" # for internet
```

Please consult your cloud provider for more accurate and update-to-date information.


### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator

##### Step 1: Installing the Prometheus Operator

- Create a new namespace for Prometheus Operator using the following command:

```bash
kubectl create namespace monitoring
```

- Add the Prometheus Operator Helm repository:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
```

- Install the Prometheus Operator using the following command:

```bash
helm install prometheus-operator prometheus-community/kube-prometheus-stack --namespace monitoring
```

##### Step 2: Verifying the Deployment

- Verify the deployment of the Prometheus Operator using the following command:

```bash
kubectl get pods -n monitoring
```

##### Step 3: Accessing the Prometheus Dashboard

- Check the service endpoints of Prometheus and Grafana.

```bash
kubectl get svc -n monitoring
```

- Use port forwarding to access the Prometheus dashboard locally

```bash
kubectl port-forward svc/prometheus-operator-kube-p-prometheus -n monitoring 9090:9090
```

And you can access the Prometheus dashboard by opening "http://localhost:9090" in your browser.

- Similarly, use port forwarding to access the Grafana dashboard locally

```bash
kubectl port-forward svc/prometheus-operator-grafana -n monitoring 3000:80
```

and you can access the Grafana dashboard by opening "http://localhost:3000" in your browser.

To login, you may retrieve the credential from the secret:

```bash
kubectl get secrets prometheus-operator-grafana -n monitoring -oyaml
```


#### Create PodMonitor

##### Step 1. Query ScrapePath and ScrapePort

Here is the list of endpoints that can be scraped by Prometheus provided by `obagent`:

```yaml
  podMetricsEndpoints:
    - path: /metrics/stat
      port: http
      scheme: http
    - path: /metrics/ob/basic
      port: http
      scheme: http
    - path: /metrics/ob/extra
      port: http
      scheme: http
    - path: /metrics/node/ob
      port: http
      scheme: http
```

##### Step 2. Accessing the Grafana Dashboard

Apply the `PodMonitor` file to monitor the cluster:

```bash
kubectl apply -f examples/oceanbase/pod-monitor.yaml
```

##### Step 3. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard.

There is a pre-configured dashboard for PostgreSQL under the `APPS / OceanBase Mertrics` folder in the Grafana dashboard.

> [!Note] Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.


### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster ob-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster ob-cluster
```


## References

[^1]: OceanBase Backup, https://en.oceanbase.com/docs/common-oceanbase-database-10000000001231357
[^2]: OceanBase, https://en.oceanbase.com/docs/common-oceanbase-database-10000000001228198