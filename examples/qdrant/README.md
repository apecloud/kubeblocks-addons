# Qdrant on KubeBlocks

## Overview

Qdrant is an open-source vector search engine and vector database designed for efficient similarity search and storage of high-dimensional vectors. It is optimized for AI-driven applications, such as semantic search, recommendation systems, and retrieval-augmented generation (RAG) in large language models (LLMs).

## Features in KubeBlocks

### Cluster Management Operations

| Operation |Supported | Description |
|-----------|-------------|----------------------|
| **Restart** | YES | • Ordered sequence (followers first)<br/>• Health checks between restarts |
| **Stop/Start** | YES |  • Graceful shutdown<br/>• Fast startup from persisted state |
| **Horizontal Scaling** |YES |  • Adjust replica count dynamically<br/>• Automatic data replication<br/> |
| **Vertical Scaling** | YES |  • Adjust CPU/Memory resources<br/>• Rolling updates for minimal downtime<br/>• Adaptive Parameters Reconfiguration, such as buffer pool size/max connections |
| **Volume Expansion** | YES |  • Online storage expansion<br/>• No downtime required |
| **Reconfiguration** | NO | • Dynamic/Static parameter updates<br/>• Validation rules<br/>• Versioned history |
| **Service Exposure** | YES |  • Multiple exposure types (ClusterIP/NodePort/LB)<br/>• Role-based routing |
| **Switchover** | N/A |  • Planned primary transfer<br/>• Zero data loss guarantee |

### Data Protection

| Type       | Method     | Details |
|-------------|--------|------------|
| Full Backup | datafile | uses HTTP API `snapshot` to create snapshot for all collections. |

### Supported Versions

| Major Versions | Minor Versions|
|---------------|-------------|
| 1.5 | 1.5.0 |
| 1.7 | 1.7.3 |
| 1.8 | 1.8.1,1.8.4 |
| 1.10| 1.10.0 |

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes Environment**:
   - Cluster v1.21+
   - `kubectl` installed ([Installation Guide](https://kubernetes.io/docs/tasks/tools/))
   - Helm v3+ ([Installation Guide](https://helm.sh/docs/intro/install/))

2. **KubeBlocks Setup**:
   - KubeBlocks installed and running ([Installation](../docs/prerequisites.md))
   - Qdrant Addon enabled ([Addon Setup](../docs/install-addon.md))

3. **Namespace Setup**:
   Create an isolated namespace for this tutorial:

  ```bash
  kubectl create ns demo
  ```

## Lifecycle Management Operations

### Cluster Provisioning

#### Quick Start

To deploy a basic Qdrant replication cluster:

```bash
kubectl apply -f examples/qdrant/cluster.yaml
```

And you will see the Qdrant cluster status goes `Running` after a while:

```bash
kubectl get cluster qdrant-cluster -w -n demo
```

<details open>
<summary>Expected Output</summary>

```bash
NAME             CLUSTER-DEFINITION   TERMINATION-POLICY   STATUS     AGE
qdrant-cluster   qdrant               Delete               Running    120s
```

</details>

#### Version-Specific Cluster

If you want to create a cluster of specified version, set the `spec.componentSpecs.serviceVersion` field in the yaml file before applying it:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: qdrant
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      serviceVersion: "1.10.0" # more Qdrant versions will be supported in the future
```

The list of supported versions can be found by following command:

```bash
kubectl get cmpv qdrant
```

<details open>
<summary>Expected Output</summary>

```bash
NAME     VERSIONS                         STATUS      AGE
qdrant   1.10.0,1.8.4,1.8.1,1.7.3,1.5.0   Available   20d
```

</details>

### Cluster Restart

Restart the cluster components with zero downtime:

```bash
kubectl apply -f examples/qdrant/restart.yaml
```

This operation can only be performed via `OpsRequest`, and there is no corresponding CLUSTER API operation - because restart is not a declaration but an action.

### Cluster Stop and Start

#### Stopping the Cluster

Gracefully stop the cluster to conserve resources while retaining all data (PVC). It is ideal for cost savings during inactive periods.

**Stop via OpsRequest**

```bash
kubectl apply -f examples/qdrant/stop.yaml
```

> [!NOTE]
> When stopped:
>
> - All compute resources are released
> - Persistent volumes remain intact
> - No data is lost

**Stop via Cluster API**

Update the cluster spec directly:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: qdrant
      stop: true  # Set to true to stop the component
      replicas: 3
```

#### Starting the Cluster

Start the cluster from its stopped state:

**Start via OpsRequest**

```bash
kubectl apply -f examples/qdrant/start.yaml
```

**Start via Cluster API**

Update the cluster spec directly:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: qdrant
      stop: false  # Set to false to start the component or remove the field (default to false)
      replicas: 3
```

## Scaling Operations

### Horizontal Scaling

> [!Important]
> Qdrant uses the **Raft consensus protocol** to maintain consistency regarding the cluster topology and the collections structure.
> Make sure to have an odd number of replicas, such as 3, 5, 7, to avoid split-brain scenarios, after scaling out/in the cluster.

#### Scale Out Operation

Add a new replica to the cluster:

```bash
kubectl apply -f examples/qdrant/scale-out.yaml
```

To Check detailed operation status

```bash
kubectl describe ops -n demo qdrant-scale-out
```

**Expected Workflow**:

1. New pod is provisioned with `Pending` status
2. Cluster status changes from `Updating` to `Running`

### Scale In Operation

> [!IMPORTANT]
> On scale-in, data will be redistributed among the remaining replicas. Make sure the cluster have enough capacity to accommodate the data.
> The data redistribution process may take some time depending on the amount of data.
> It is handled by Qdrant `MemberLeave` operation, and Pods won't be deleted until the data redistribution, i.e. the `MemberLeave` actions completed successfully.

<details>
<summary>Developer: How MemberLeave works </summary>

1. Cluster Information Gathering:

- Identifies the leaving member via KB_LEAVE_MEMBER_POD_FQDN
- Retrieves cluster state including peer IDs and leader information

2. Data Migration:

- Discovers all collections on the leaving member
- For each collection, finds all local shards
- Moves each shard to the cluster leader
- Verifies successful shard transfer before proceeding

3. Cluster Membership Update:

- Removes the leaving peer from the cluster membership
- Uses file locking to prevent concurrent removal operations

</details>

#### Standard Scale In Operation

Remove a replica from the cluster:

```bash
kubectl apply -f examples/qdrant/scale-in.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo qdrant-scale-in
```

**Expected Workflow**:

1. Selected replica (the one with the largest ordinal) is removed
2. Pod is terminated gracefully
3. Cluster status changes from `Updating` to `Running`

**Verification**:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=qdrant-cluster
```

#### Horizontal Scaling via Cluster API

Directly update replica count via Cluster API:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: qdrant
      replicas: 2  # Adjust replicas for scaling in and out.
```

### Vertical Scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:

- CPU cores/processing power
- Memory (RAM)

#### Vertical Scaling via OpsRequest API

Perform vertical scaling using a operation request:

```bash
kubectl apply -f examples/qdrant/verticalscale.yaml
```

#### Vertical Scaling via Cluster API

Directly modify cluster specifications for vertical scaling:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: qdrant
      resources:
        requests:
          cpu: "1"       # CPU cores (e.g. "1", "500m")
          memory: "2Gi"  # Memory (e.g. "2Gi", "512Mi")
        limits:
          cpu: "2"       # Maximum CPU allocation
          memory: "4Gi"  # Maximum memory allocation
```

**Key Considerations**:

- Ensure sufficient cluster capacity exists
- Resource changes may trigger pod restarts and parameters reconfiguration
- Monitor resource utilization after changes

## Storage Operations

### Prerequisites

Volume expansion is the ability to increase the size of a Persistent Volume Claim (PVC) after it's created. It is introduced in Kubernetes v1.11 and goes GA in Kubernetes v1.24. It allows Kubernetes users to simply edit their PersistentVolumeClaim objects without requiring any downtime at all if possible.

> [!NOTE]
> Make sure the storage class you used when creating clusters supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

### Volume Expansion

#### Volume Expansion via OpsRequest API

To increase size of volume storage with the specified components in the cluster

```bash
kubectl apply -f examples/qdrant/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=qdrant-cluster -n demo
```

#### Volume Expansion via Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: qdrant
      volumeClaimTemplates:
        - name: data
          spec:
            storageClassName: "<STORAGE_CLASS_NAME>"
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 30Gi  # specify new size, and make sure it is larger than the current size
```

> [!NOTE]
> If the storage class you use does not support volume expansion, this OpsRequest fails fast with information like:
> `storageClass: [STORAGE_CLASS_NAME] of volumeClaimTemplate: [VOLUME_NAME]] not support volume expansion in component [COMPONENT_NAME]`

## Networking

### Service Exposure

#### Expose SVC via Cluster API

Alternatively, you may expose service by adding a new service to cluster's `spec.services`:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  services:
    - annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: nlb
      componentSelector: qdrant
      name: qdrant-vpc
      serviceName: qdrant-vpc
      spec:
        ports:
        - name: qdrant
          port: 6333
          protocol: TCP
          targetPort: tcp-qdrant
        type: LoadBalancer  # [ClusterIP, NodePort, LoadBalancer]
```

#### Cloud Provider Load Balancer Annotations

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

## Data Protection Operations

### Prerequisites

1. **Backup Repository**:
   - Configured `BackupRepo` ([Setup Guide](../docs/create-backuprepo.md))
   - Network connectivity between cluster and repo, `BackupRepo` status is `Ready`

2. **Cluster State**:
   - Cluster must be in `Running` state
   - No ongoing operations (scaling, upgrades etc.)

### Backup Operations

#### Backup Configuration

1. **View default Backup Policies**:

   ```bash
   kubectl get backuppolicy -n demo -l app.kubernetes.io/instance=qdrant-cluster
   ```

2. **View default BackupSchedule**:

   ```bash
   kubectl get backupschedule -n demo -l app.kubernetes.io/instance=qdrant-cluster
   ```

#### Full Backup: datafile

The backup method uses the `snapshot` API to create a snapshot for all collections. It works as follows:

- Retrieve all Qdrant collections
- For each collection, create a snapshot, validate the snapshot, and push it to the backup repository

1. **On-Demand Backup**:

   ```bash
   kubectl apply -f examples/qdrant/backup.yaml
   ```

2. **Monitor Progress**:

   ```bash
   kubectl get backup -n demo -w
   kubectl describe backup <backup-name> -n demo
   ```

3. **Verify Completion**:
   - Check status is `Completed`
   - Verify backup size matches expectations
   - Validate backup metadata

#### Scheduled Backups

Update `BackupSchedule` to schedule enable(`enabled`) backup methods and set the time (`cronExpression`) to your need:

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
spec:
  backupPolicyName: qdrant-cluster-qdrant-backup-policy
  schedules:
  - backupMethod: datafile
    # ┌───────────── minute (0-59)
    # │ ┌───────────── hour (0-23)
    # │ │ ┌───────────── day of month (1-31)
    # │ │ │ ┌───────────── month (1-12)
    # │ │ │ │ ┌───────────── day of week (0-6) (Sunday=0)
    # │ │ │ │ │
    # 0 18 * * *
    # schedule this job every day at 6:00 PM (18:00).
    cronExpression: 0 18 * * * # update the cronExpression to your need
    enabled: true # set to `true` to schedule base backup periodically
    retentionPeriod: 7d # set the retention period to your need
```

#### Troubleshooting

- **Backup Stuck**:

  ```bash
  kubectl describe backup <name> -n demo  # describe backup
  kubectl get po -n demo -l app.kubernetes.io/instance=qdrant-cluster,dataprotection.kubeblocks.io/backup-policy=qdrant-cluster-qdrant-backup-policy # get list of pods working for Backups
  kubectl logs -n demo <backup-pod> # check backup pod logs
  ```

### Restore Operations

#### Prerequisites

1. **Backup Verification**:

2. **Cluster Resources**:
   - Sufficient CPU/memory for new cluster
   - Available storage capacity
   - Network connectivity between backup repo and new cluster

#### Restore from a Full Backup

1. **Identify Backup**:

   ```bash
   kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Full,app.kubernetes.io/instance=qdrant-cluster # get the list of full backups
   ```

2. **Configure Restore**:
   Update `examples/qdrant/restore.yaml` with:
   - Backup name and namespace: from step 1
   - Target cluster configuration

3. **Execute Restore**:

   ```bash
   kubectl apply -f examples/qdrant/restore.yaml
   ```

4. **Monitor Progress**:

   ```bash
   # Watch restore status
   kubectl get restore -n demo -w

   # View detailed logs
   kubectl get cluster -n demo -w
   ```

## Monitoring & Observability

### Prerequisites

1. **Prometheus Operator**: Required for metrics collection
   - Skip if already installed
   - Install via: [Prometheus Operator Guide](../docs/install-prometheus.md)

2. **Access Credentials**: Ensure you have:
   - `kubectl` access to the cluster
   - Grafana admin privileges (for dashboard import)

### Metrics Collection Setup

#### 1. Configure PodMonitor

Please refert to [Qdrant Monitoring & Telemetry](https://qdrant.tech/documentation/guides/monitoring/) for more details.

1. **Verify Metrics Endpoint**:

  ```bash
  kubectl -n demo exec -it pods/qdrant-cluster-qdrant-0 -c kbagent -- \
    curl -s http://127.0.0.1:6333/metrics | head -n 50
  ```

2. **Apply PodMonitor**:

  ```bash
  kubectl apply -f examples/qdrant/pod-monitor.yaml
  ```

It sets path to `/metrics` and port to `tcp-qdrant` (for container port `6333`).

```yaml
    - path: /metrics
      port: tcp-qdrant
      scheme: http
```

#### 2. Grafana Dashboard Setup

1. **Import Dashboard**:
   - URL: [Qdrant Dashboard](https://raw.githubusercontent.com/apecloud/kubeblocks-addons/refs/heads/main/addons/qdrant/dashboards/qdrant-overview.json)

2. **Verification**:
   - Confirm metrics appear in Grafana within 2-5 minutes
   - Check for "UP" status in Prometheus targets

### Troubleshooting

- **No Metrics**: check Prometheus

  ```bash
  kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
  kubectl logs -n monitoring <prometheus-pod-name> -c prometheus
  ```

- **Dashboard Issues**: check metrics labels and dashboards
  - Verify Grafana DataSource points to correct Prometheus instance
  - Check for template variable mismatches

## Cleanup

To permanently delete the cluster and all associated resources:

1. First modify the termination policy to ensure all resources are cleaned up:

```bash
# Set termination policy to WipeOut (deletes all resources including PVCs)
kubectl patch cluster -n demo qdrant-cluster \
  -p '{"spec":{"terminationPolicy":"WipeOut"}}' \
  --type="merge"
```

2. Verify the termination policy was updated:

```bash
kubectl get cluster -n demo qdrant-cluster -o jsonpath='{.spec.terminationPolicy}'
```

3. Delete the cluster:

```bash
kubectl delete cluster -n demo qdrant-cluster
```

> [!WARNING]
> This operation is irreversible and will permanently delete:
>
> - All database pods
> - Persistent volumes and claims
> - Services and other cluster resources

<details open>
<summary>How to set a proper `TerminationPolicy`</summary>

For more details you may use following command

```bash
kubectl explain cluster.spec.terminationPolicy
```

| Policy            | Description                                                                                                                                               |
|-------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| `DoNotTerminate`  | Prevents deletion of the Cluster. This policy ensures that all resources remain intact.                                                                   |
| `Delete`          | Deletes all runtime resources belonging to the Cluster.                                                                                                   |
| `WipeOut`         | An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss. |

</details>

## Appendix

### Connecting to Qdrant

To connect to the Qdrant cluster, you can:

- port forward the Qdrant service to your local machine:

```bash
kubectl port-forward svc/qdrant-cluster-qdrant 6333:6333 -n demo
```

- or expose the Qdrant service to the internet, as mentioned in the [Networking](#networking) section.

Then you can manage the qdrant with its WebUI:

- navigate to `http://<endpoint>:6333/dashboard`

### List of K8s Resources created when creating an Qdrant Cluster

To get the full list of associated resources created by KubeBlocks for given cluster:

```bash
kubectl get cmp,its,po -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # cluster and worload
kubectl get backuppolicy,backupschedule,backup -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # data protection resources
kubectl get componentparameter,parameter -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # configuration resources
kubectl get opsrequest -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # opsrequest resources
kubectl get svc,secret,cm,pvc -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # k8s native resources
```

### Developer: How to Add a new Version to Qdrant

Qdrant releases new minor versions frequently (approximately monthly). If the currently provided v1.10.0 doesn't meet your requirements, you can easily add a new compatible version to the Qdrant Addon.

for instance, you can simply update the `ComponentVersion` to add support for v1.14.0 version:

```text
--- a/addons/qdrant/templates/cmpv.yaml
+++ b/addons/qdrant/templates/cmpv.yaml
@@ -16,6 +16,7 @@ spec:
     - 1.8.1
     - 1.8.4
     - 1.10.0
+    - 1.14.0
   releases:
   - name: 1.5.0
     serviceVersion: 1.5.0
@@ -47,3 +48,9 @@ spec:
       qdrant: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository}}:v1.10.0
       qdrant-tools:  {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.tools.repository }}:{{ .Values.image.tools.tag | default "latest" }}
       memberleave: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.tools.repository }}:{{ .Values.image.tools.tag | default "latest" }}
+  - name: 1.14.0
+    serviceVersion: 1.14.0
+    images:
+      qdrant: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository}}:v1.14.0
+      memberleave:  {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.tools.repository }}:{{ .Values.image.tools.tag | default "latest" }}
+      qdrant-tools: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.tools.repository }}:{{ .Values.image.tools.tag | default "latest" }}
```

where `qdrant-tools` is the sidecar container, and and `memberleave` is for the member leave action.
Both of them are a tools image for providing `curl` and `jq` commands.

### Developer: Minimal dependency RAG with DeepSeek and Qdrant

You may refer to [Minimal dependency RAG with DeepSeek and Qdrant](./test/deepseek-qdrant.ipynb) , a copy from Qdrant github repo[^1] to build you minimal dependency RAG.
Before you start, please expose the service using port-forward locally.

## References

[^1]: Qdrant Repo: <https://github.com/qdrant>
