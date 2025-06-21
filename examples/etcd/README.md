# etcd

etcd is a distributed, highly available key-value store designed to securely store data across a cluster of machines. It provides strong consistency guarantees, ensuring that data is reliably replicated and synchronized among all nodes. etcd is commonly used for configuration management, service discovery, and coordinating distributed systems. Its simplicity and robustness make it a critical component in cloud-native environments, particularly within Kubernetes for maintaining cluster state and configuration.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal``scaling | Vertical``scaling | Expand``volume | Restart | Stop/Start | Configure | Expose | Switchover |
| -------------------------- | ------------------------ | --------------------- | ------- | ---------- | --------- | ------ | ---------- |
| Yes                        | Yes                      | Yes                   | Yes     | Yes        | Yes       | Yes    | Yes        |

### Backup and Restore

| Feature     | Method   | Description                                                                  |
| ----------- | -------- | ---------------------------------------------------------------------------- |
| Full Backup | datafile | using `etcdcl snapshot save` to create snapshot of the etcd cluster's data |

### Versions

| Major Versions | Description  |
| -------------- | ------------ |
| 3.5.x          | 3.5.6,3.5.15 |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- ETCD Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### [Create](cluster.yaml)

Create an etcd cluster with three replicas, one leader and two followers.

```bash
kubectl apply -f examples/etcd/cluster.yaml
```

#### Create with TLS Enabled

To create etcd cluster with TLS enabled,

```bash
kubectl apply -f examples/etcd/cluster-with-tls.yaml
```

Compared to the default configuration, the only difference here is the `tls` and `issuer` fields in the `cluster-with-tls.yaml` file.

```yaml
tls: true  # enable tls
issuer:    # set issuer, could be 'KubeBlocks' or 'UserProvided'
  name: KubeBlocks
```

By default, the `issuer` is set to `KubeBlocks`, which means KubeBlocks will generate the certificates for you and store it in a secret, `<clusterName>-<componentName>-tls-certs`.
If you want to use your own certificates, you can set the `issuer` to `UserProvided` and provide the certificates in the `secretRef` field.

Certifications are mounted to path '/etc/pki/tls' by default. To check how secrets will be mounted, you may check the TLS field in `ComponentDefinition`:

```bash
kubectl get cmpd <cmpdName> -oyaml | yq '.spec.tls'
```

<details>
<summary>Expected Output</summary>

```bash
caFile: ca.pem
certFile: cert.pem
keyFile: key.pem
mountPath: /etc/pki/tls
volumeName: tls
```

</details>

Here is a simple test to verify if TLS works.

- login a read/write ETCD pod (with role=leader)

```bash
kubectl get po  -n demo -l kubeblocks.io/role=leader,apps.kubeblocks.io/component-name=etcd
kubectl exec -n demo -it <podName> -- /bin/bash
```

- put values

```bash
etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/pki/tls/ca.pem \
  --cert=/etc/pki/tls/cert.pem \
  --key=/etc/pki/tls/key.pem \
  put foo bar
```

- get values

```bash
etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/pki/tls/ca.pem \
  --cert=/etc/pki/tls/cert.pem \
  --key=/etc/pki/tls/key.pem \
  get foo
```

<details>
<summary>Expected Output</summary>

```bash
foo
bar
```

</details>

### [Create with LoadBalancer](cluster-with-lb.yaml)

Create an etcd cluster with LoadBalancer services for enhanced external accessibility and multi-cluster communication.

Ensure your Kubernetes cluster has a LoadBalancer provider configured:

- **Cloud providers**: AWS ELB, Azure Load Balancer, GCP Cloud Load Balancing
- **On-premises**: MetalLB, HAProxy, NGINX Ingress Controller
- **Other**: Any compatible LoadBalancer implementation
- **Peer Service LoadBalancer**: Enables etcd members to communicate across different networks or clusters
- **Client Service LoadBalancer**: Provides a stable external endpoint for etcd client connections
- **High Availability**: External load balancing ensures resilient access to the etcd cluster

```bash
kubectl apply -f examples/etcd/cluster-with-lb.yaml
```

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out ETCD cluster by adding ONE more replica:

```bash
kubectl apply -f examples/etcd/scale-out.yaml
```

After applying the operation, you will see a new pod created and the cluster status goes from `Updating` to `Running`, and the newly created pod has a new role `follower`.

And you can check the progress of the scaling operation with following command:

```bash
kubectl describe ops -n demo etcd-scale-out
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in etcd cluster by deleting ONE replica:

```bash
kubectl apply -f examples/etcd/scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: etcd
      replicas: 3 # Update `replicas` to 1 for scaling in, and to 3 for scaling out
```

### [Reconfigure](configure.yaml)

Reconfigure parameters with the specified components in the cluster

```bash
kubectl apply -f examples/etcd/configure.yaml
```

This example will modify several etcd configuration parameters including snapshot settings and logging levels.

To verify the configuration changes, you can check the etcd configuration and cluster status:

```bash
# Check the OpsRequest status
kubectl get opsrequest etcd-reconfiguring -n demo

# View the updated ConfigMap
kubectl get configmap etcd-cluster-etcd-config -n demo -o yaml

# Connect to an etcd pod to verify cluster health
kubectl exec -it etcd-cluster-etcd-0 -n demo -- etcdctl endpoint health

# Check etcd member list and status
kubectl exec -it etcd-cluster-etcd-0 -n demo -- etcdctl member list
```

<details>
<summary>Explanation of the configuration</summary>

The etcd configuration is stored in a YAML file (`etcd.conf`) that controls various aspects of the etcd cluster behavior.

When updating the configuration, the parameter keys in the `configure.yaml` file must use the `etcd.` prefix followed by the configuration parameter name:

```yaml
# snippet of configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
spec:
  reconfigures:
  - componentName: etcd
    parameters:
    - key: etcd.max-snapshots
      value: '10'
    - key: etcd.max-wals
      value: '10'
    - key: etcd.log-level
      value: 'info'
    - key: etcd.auto-compaction-retention
      value: '2'
```

#### Parameter Classification

**Static Parameters (Require Restart):**
Most etcd parameters are static and require an etcd process restart to take effect. These include:

**Performance & Storage:**
- `etcd.max-snapshots`: Maximum snapshot files to retain
- `etcd.max-wals`: Maximum WAL files to retain  
- `etcd.snapshot-count`: Transaction count to trigger snapshot
- `etcd.quota-backend-bytes`: Backend storage quota
- `etcd.data-dir`: Path to the data directory
- `etcd.wal-dir`: Path to the dedicated wal directory

**Timing Parameters:**
- `etcd.heartbeat-interval`: Heartbeat interval (ms)
- `etcd.election-timeout`: Election timeout (ms)

**Logging:**
- `etcd.log-level`: Log level (debug, info, warn, error, panic, fatal)
- `etcd.log-outputs`: Log output destinations
- `etcd.logger`: Logger type (capnslog, zap)

**Auto Compaction:**
- `etcd.auto-compaction-mode`: Compaction mode (periodic, revision)
- `etcd.auto-compaction-retention`: Retention period/revision count

**Network & Security:**
- `etcd.listen-peer-urls`: URLs to listen on for peer traffic
- `etcd.listen-client-urls`: URLs to listen on for client traffic
- `etcd.advertise-client-urls`: Client URLs to advertise to the public
- `etcd.initial-advertise-peer-urls`: Peer URLs to advertise to the cluster
- `etcd.cors`: CORS whitelist origins
- `etcd.enable-pprof`: Enable runtime profiling
- `etcd.strict-reconfig-check`: Reject reconfiguration requests that cause quorum loss

**Proxy Configuration:**
- `etcd.proxy`: Proxy mode (off, readonly, on)
- `etcd.proxy-failure-wait`: Endpoint failure wait time (ms)
- `etcd.proxy-refresh-interval`: Endpoint refresh interval (ms)
- `etcd.proxy-dial-timeout`: Dial timeout (ms)
- `etcd.proxy-write-timeout`: Write timeout (ms)
- `etcd.proxy-read-timeout`: Read timeout (ms)

**Discovery:**
- `etcd.discovery`: Discovery URL for bootstrapping
- `etcd.discovery-fallback`: Discovery fallback behavior
- `etcd.discovery-proxy`: HTTP proxy for discovery service
- `etcd.discovery-srv`: DNS domain for discovery

**TLS & Security:**
- `etcd.self-signed-cert-validity`: Self-signed certificate validity (years)
- `etcd.cipher-suites`: TLS cipher suites
- `etcd.tls-min-version`: Minimum TLS version
- `etcd.tls-max-version`: Maximum TLS version
- `etcd.client-transport-security`: Client TLS configuration
- `etcd.peer-transport-security`: Peer TLS configuration

**Dynamic Parameters:**
Currently, only member management operations are supported for dynamic configuration through etcdctl.

**Immutable Parameters:**
The following parameters cannot be changed after cluster creation:
- `etcd.initial-cluster`: Initial cluster configuration
- `etcd.initial-cluster-token`: Initial cluster token
- `etcd.initial-cluster-state`: Initial cluster state
- `etcd.force-new-cluster`: Force new cluster creation

</details>

### [Vertical scaling](verticalscale.yaml)

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:, CPU cores/processing power and Memory (RAM).

To vertical scaling up or down specified component, you can apply the following yaml file:

```bash
kubectl apply -f examples/etcd/verticalscale.yaml
```

You will observe that the `follower` pod is recreated first, followed by the `leader` pod, to ensure the availability of the cluster.

#### Scale-up/down using Cluster API

Alternatively, you may update `spec.componentSpecs.resources` field to the desired resources for vertical scale.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: etcd
      replicas: 3
      resources:
        requests:
          cpu: "1"       # Update the resources to your need.
          memory: "2Gi"  # Update the resources to your need.
        limits:
          cpu: "2"       # Update the resources to your need.
          memory: "4Gi"  # Update the resources to your need.
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
kubectl apply -f examples/etcd/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=etcd-cluster -n demo
```

#### Volume expansion using Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: etcd
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: "<you-preferred-sc>"
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 30Gi  # specify new size, and make sure it is larger than the current size
```

### [Restart](restart.yaml)

Restart the specified components in the cluster, and instances will be recreated on after another to ensure the availability of the cluster

```bash
kubectl apply -f examples/etcd/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster will release all the pods of the cluster, but the storage will be retained. It is useful when you want to save the cost of the cluster.

```bash
kubectl apply -f examples/etcd/stop.yaml
```

#### Stop using Cluster API

Alternatively, you may stop the cluster by setting the `spec.componentSpecs.stop` field to `true`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: etcd
      stop: true  # set stop `true` to stop the component
      replicas: 2
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/etcd/start.yaml
```

#### Start using Cluster API

Alternatively, you may start the cluster by setting the `spec.componentSpecs.stop` field to `false`.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: etcd
      stop: false  # set to `false` (or remove this field) to start the component
      replicas: 2
```

### [Switchover](switchover.yaml)

A switchover in database clusters is a planned operation that transfers the primary (leader) role from one database instance to another. The goal of a switchover is to ensure that the database cluster remains available and operational during the transition.

To perform a switchover, you can apply the following yaml file:

```bash
kubectl apply -f examples/etcd/switchover.yaml
```

### [Backup](backup.yaml)

You may find the list of supported Backup Methods:

```bash
# etcd-cluster-etcd-backup-policy is the backup policy name
kubectl get bp -n demo etcd-cluster-etcd-backup-policy -oyaml | yq '.spec.backupMethods[].name'
```

The method `datafile` uses `etcdctl snapshot save` to do a full backup. You may create a backup using:

```bash
kubectl apply -f examples/etcd/backup.yaml
```

After the operation, you will see a `Backup` is created

```bash
kubectl get backup -n demo -l app.kubernetes.io/instance=etcd-cluster
```

and the status of the backup goes from `Running` to `Completed` after a while. And the backup data will be pushed to your specified `BackupRepo`.

### [Restore](restore.yaml)

To restore a new cluster from a Backup:

```bash
kubectl apply -f examples/etcd/restore.yaml
```

### Observability

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

##### Step 1. Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```bash
kubectl apply -f examples/etcd/pod-monitor.yaml
```

It sets path to `/metrics` and port to `client` (for container port `2379`).

```yaml
  - path: /metrics
    port: client
    scheme: http
```

##### Step 2. Accessing the Grafana Dashboard

Login to the Grafana dashboard and import the dashboard, e.g. using etcd dashboard from [Grafana](https://grafana.com/grafana/dashboards).

> [!NOTE]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster -n demo etcd-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster -n demo etcd-cluster
```
