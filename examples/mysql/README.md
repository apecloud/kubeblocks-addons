# MySQL on KubeBlocks

## Overview

MySQL is one of the most popular open-source relational database management systems (RDBMS). It is widely used for web applications and acts as the database component of the LAMP (Linux, Apache, MySQL, PHP/Python/Perl) stack. Developed by Oracle Corporation, MySQL is known for its speed, reliability, and ease of use. It supports a wide range of platforms, including Linux, Windows, macOS, and various Unix variants.

## Features in KubeBlocks

### Cluster Management Operations

| Operation |Supported | Description |
|-----------|-------------|----------------------|
| **Restart** | YES | • Ordered sequence (followers first)<br/>• Health checks between restarts |
| **Stop/Start** | YES |  • Graceful shutdown<br/>• Fast startup from persisted state |
| **Horizontal Scaling** |YES |  • Adjust replica count dynamically<br/>• Automatic data replication<br/> |
| **Vertical Scaling** | YES |  • Adjust CPU/Memory resources<br/>• Rolling updates for minimal downtime<br/>• Adaptive Parameters Reconfiguration, such as buffer pool size/max connections |
| **Volume Expansion** | YES |  • Online storage expansion<br/>• No downtime required |
| **Reconfiguration** | YES | • Dynamic/Static parameter updates<br/>• Validation rules<br/>• Versioned history |
| **Service Exposure** | YES |  • Multiple exposure types (ClusterIP/NodePort/LB)<br/>• Role-based routing |
| **Switchover** | YES |  • Planned primary transfer<br/>• Zero data loss guarantee |

### Data Protection

| Type       | Method     | Details |
|---------------|------------|---------|
| Full Backup   | xtrabackup | • using Percona XtraBackup to perform a full backup <br/>• Upload backup file using `datasafed push`
| Continuous Backup | archive-binlog | • Flushes binlogs when needed (size or time thresholds) <br/> • Upload binlogs using `wal-g binlog-push` <br/> • Purges expired binlogs |

### Supported Versions

| MySQL Version | MySQL Version | Notes |
|--------------|-----------------------|-------|
| 8.0.30       | 8.0.30 | GA release |

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes Environment**:
   - Cluster v1.21+
   - `kubectl` installed ([Installation Guide](https://kubernetes.io/docs/tasks/tools/))
   - Helm v3+ ([Installation Guide](https://helm.sh/docs/intro/install/))

2. **KubeBlocks Setup**:
   - KubeBlocks installed and running ([Installation](../docs/prerequisites.md))
   - MySQL Addon enabled ([Addon Setup](../docs/install-addon.md))

3. **Namespace Setup**:
   Create an isolated namespace for this tutorial:

  ```bash
  kubectl create ns demo
  ```

## Lifecycle Management Operations

### Cluster Provisioning

#### Quick Start

To deploy a basic MySQL cluster with RAFT consensus:

```bash
kubectl apply -f examples/mysql/cluster.yaml
```

And you will see the MySQL cluster status goes `Running` after a while:

```bash
kubectl get cluster mysql-cluster -w -n demo
```

<details open>
<summary>Expected Output</summary>

```bash
NAME              CLUSTER-DEFINITION   TERMINATION-POLICY   STATUS    AGE
mysql-cluster                          Delete               Running   1m
```

</details>

and these two replicas are `Running` with roles `primary`,  `secondary` separately. To check the roles of the replicas, you can use following command:

```bash
kubectl get po -l  app.kubernetes.io/instance=mysql-cluster -L kubeblocks.io/role -n demo
```

<details open>
<summary>Expected Output</summary>

```bash
NAME                      READY   STATUS    RESTARTS   AGE   ROLE
mysql-cluster-mysql-0     4/4     Running   0          99s   primary
mysql-cluster-mysql-1     4/4     Running   0          85s   secondary
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
    - name: mysql
      # ServiceVersion specifies the version of the Service expected to be
      # provisioned by this Component.
      serviceVersion: "8.0.35" # more MySQL versions will be supported in the future
```

The list of supported versions can be found by following command:

```bash
kubectl get cmpv mysql
```

<details open>
<summary>Expected Output</summary>

```bash
NAME    VERSIONS                                                                                         STATUS      AGE
mysql   8.4.2,8.4.1,8.4.0,8.0.39,8.0.38,8.0.37,8.0.36,8.0.35,8.0.34,8.0.33,8.0.32,8.0.31,8.0.30,5.7.44   Available   5d
```

</details>

### Cluster Restart

Restart the cluster components with zero downtime:

```bash
kubectl apply -f examples/mysql/restart.yaml
```

This operation can only be performed via `OpsRequest`, and there is no corresponding CLUSTER API operation - because restart is not a declaration but an action.

> [!NOTE]
> The restart follows a safe sequence:
>
> 1. All secondary replicas are restarted first
> 2. Primary replica is restarted last
> 3. Transfer leadership to a healthy secondary before restarting Primary replica
> This ensures continuous availability during the restart process.

### Cluster Stop and Start

#### Stopping the Cluster

Gracefully stop the cluster to conserve resources while retaining all data (PVC). It is ideal for cost savings during inactive periods.

**Stop via OpsRequest**

```bash
kubectl apply -f examples/mysql/stop.yaml
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
    - name: mysql
      stop: true  # Set to true to stop the component
      replicas: 2
```

#### Starting the Cluster

Start the cluster from its stopped state:

**Start via OpsRequest**

```bash
kubectl apply -f examples/mysql/start.yaml
```

**Start via Cluster API**

Update the cluster spec directly:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mysql
      stop: false  # Set to false to start the component or remove the field (default to false)
      replicas: 2
```

## Scaling Operations

### Horizontal Scaling

> [!NOTE]
> As per the MySQL documentation, the number of Raft replicas should be odd to avoid split-brain scenarios.
> Make sure the number of MySQL replicas, is always odd after Horizontal Scaling.

#### Scale Out Operation

Add a new replica to the cluster:

```bash
kubectl apply -f examples/mysql/scale-out.yaml
```

To Check detailed operation status

```bash
kubectl describe ops -n demo mysql-scale-out
```

**Expected Workflow**:

1. New pod is provisioned with `Pending` status
2. Data is cloned from primary to new replica
3. New pod transitions to `Running` with `secondary` role
4. Cluster status changes from `Updating` to `Running`

> [!IMPORTANT]
> Scaling considerations:
>
> - Scaling operations are sequential - one replica at a time
> - Data cloning may take time depending on dataset size

To verify the new replica's status:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=mysql-cluster -L kubeblocks.io/role
```

### Scale In Operation

> [!NOTE]
> If the replica being scaled-in happens to be the primary replicas, KubeBlocks will trigger a SwitchOver action (if defined).

#### Standard Scale In Operation

Remove a replica from the cluster:

```bash
kubectl apply -f examples/mysql/scale-in.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo mysql-scale-in
```

**Expected Workflow**:

1. Selected replica (the one with the largest ordinal) is removed
2. Pod is terminated gracefully
3. Cluster status changes from `Updating` to `Running`

**Verification**:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=mysql-cluster
```

#### Targeted Instance Scale In

For cases where you need to take a specific problematic replica offline for maintenance:

```bash
kubectl apply -f examples/mysql/scale-in-specified-pod.yaml
```

Check detailed operation status:

```bash
kubectl describe ops -n demo mysql-scale-in-specified-pod
```

**Expected Workflow**:

1. Selected replica (specified in `onlineInstancesToOffline`) is removed
2. Pod is terminated gracefully
3. Cluster status changes from `Updating` to `Running`
4. cluster spec has been updated to:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    name: mysql
    offlineInstances:
      - mysql-cluster-mysql-1  # the instance name specified in opsrequest
    replicas: 1  # replicas reduced by one at the same time.
```

#### Horizontal Scaling via Cluster API

Directly update replica count via Cluster API:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mysql
      replicas: 2  # Adjust replicas for scaling in and out.
      offlineInstances:
        - mysql-cluster-mysql-1 # for targetd-instance scale-in scenario, default to empty list.
```

### Vertical Scaling

Vertical scaling involves increasing or decreasing resources to an existing database cluster.
Resources that can be scaled include:

- CPU cores/processing power
- Memory (RAM)

#### Vertical Scaling via OpsRequest API

Perform vertical scaling using a operation request:

```bash
kubectl apply -f examples/mysql/verticalscale.yaml
```

**Expected Workflow**:

1. Secondaries are updated first (one at a time)
1. Primary is updated last after followers are healthy
1. Cluster status transitions from `Updating` to `Running`

#### Vertical Scaling via Cluster API

Directly modify cluster specifications for vertical scaling:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mysql
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

## Reconfiguration Management

### Parameter Types

A database reconfiguration is the process of modifying database parameters, settings, or configurations to improve performance, security, or availability.

| Type | Restart Required | Scope | Example Parameters |
|------|------------------|-------|--------------------|
| **Dynamic** | No | Immediate effect | `max_connections`, `innodb_buffer_pool_size` |
| **Static** | Yes | After restart | `performance_schema`, `log_bin` |

### Reconfiguration

1. **Prepare Configuration**:

```yaml
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
spec:
  clusterRef: mysql-cluster
  type: Reconfig
  reconfig:
    componentName: mysql
    configurations:
    - name: mysql-config
      parameters:
        max_connections: "600"
        innodb_buffer_pool_size: "512M"
```

2. **Apply Changes**:

```bash
kubectl apply -f examples/mysql/configure.yaml
```

3. **Monitor Progress**:

```bash
kubectl describe ops mysql-reconfiguring -n demo  # check opsrequest progress
kubectl describe parameter mysql-reconfiguring -n demo  # check parameters reconfigurion details
```

4. **Verify Changes**:

```sql
-- On primary replica
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
```

> [!IMPORTANT]
>
> - Static changes trigger rolling restarts
> - Monitor cluster health during reconfiguration

<details open>

<summary>How to find the list of dynamic/static parameters</summary>

Behavior of Parameters, including parameters scope such as dynamic/static/immutable, or parameters validation rules such as value types, ranges of values, are defined in KubeBlocks `ParameterDefinition`.

You may fetch the list of dynamic parameters for MySQL using:

```bash
kubectl get pd mysql-8.0-pd -oyaml | yq '.spec.staticParameters'
kubectl get pd mysql-8.0-pd -oyaml | yq '.spec.dynamicParameters'
```

</details>

5. **Trouble Shooting**

```bash
kubectl describe ops mysql-reconfiguring -n demo  # check opsrequest progress
kubectl describe parameter mysql-reconfiguring -n demo  # check parameters reconfigurion details
kubectl -n demo logs mysql-cluster-mysql-0 -c config-manager # check reconfig process errors if any
```

### Configuration Validation

KubeBlocks will validate the parameter values and types before applying changes.

For example, `max_connections` in mysql should obey this rule:

```
// The number of simultaneous client connections allowed. should be a integer, btw [1, 100000]
max_connections?: int & >=1 & <=100000
```

And if you somehow give a string to this value like:

```yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
spec:
  type: Reconfiguring
  clusterName: mysql-cluster
  reconfigures:
  - componentName: mysql
    parameters:
    - key: max_connections
      value: 'abc'
```

This OpsRequest fails fast with message `failed to validate updated config: [failed to parse field max_connections: [strconv.Atoi: parsing "STRING": invalid syntax]]`

## High Availability

### Switchover (Planned Primary Transfer)

SwitchOver is a controlled operation that safely transfers leadership while maintaining:

- Continuous availability
- Zero data loss
- Minimal performance impact

<details>
<summary>Developer: Switchover Actions</summary>
KubeBlocks executes SwitchOver actions defined in `componentdefinition.spec.lifecycleActions.switchover`.

To get the SwitchOver actions for MySQL:

```bash
kubectl get cmpd mysql-8.0-1.0.0-alpha.0 -oyaml | yq '.spec.lifecycleActions.switchover'
```

</details>

#### Prerequisites

- Cluster must be in `Running` state
- No ongoing maintenance operations

#### Switchover Types

1. **Automatic Switchover** (No preferred candidate):

   ```bash
   kubectl apply -f examples/mysql/switchover.yaml
   ```

2. **Targeted Switchover** (Specific instance):

   ```bash
   kubectl apply -f examples/mysql/switchover-specified-instance.yaml
   ```

   Update `opsrequest.spec.switchover.candidateName` as needed

#### Monitoring Switchover

1. **Track Progress**:

   ```bash
   kubectl get ops -n demo -w
   kubectl describe ops <switchover-name> -n demo
   ```

2. **Verify Completion**:

   ```bash
   kubectl get pods -n demo -L kubeblocks.io/role
   ```

#### Troubleshooting

- **Switchover Stuck**:

  ```bash
  kubectl logs -n demo <pod-name> -c kbagent # check on primary replica
  kubectl get events -n demo --field-selector involvedObject.name=mysql-cluster
  ```

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
kubectl apply -f examples/mysql/volumeexpand.yaml
```

After the operation, you will see the volume size of the specified component is increased to `30Gi` in this case. Once you've done the change, check the `status.conditions` field of the PVC to see if the resize has completed.

```bash
kubectl get pvc -l app.kubernetes.io/instance=mysql-cluster -n demo
```

#### Volume Expansion via Cluster API

Alternatively, you may update the `spec.componentSpecs.volumeClaimTemplates.spec.resources.requests.storage` field to the desired size.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: mysql
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

1. **Choose Exposure Method**:
   - OpsRequest API
   - Cluster API

2. **Configure Service Annotation** (if using LoadBalancer):
   - Add appropriate annotations

#### Expose SVC via OpsRequest API

- Enable Service

```bash
kubectl apply -f examples/mysql/expose-enable.yaml
```

- Disable Service

```bash
kubectl apply -f examples/mysql/expose-disable.yaml
```

#### Expose SVC via Cluster API

Alternatively, you may expose service by adding a new service to cluster's `spec.services`:

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  services:
    - annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: nlb  # Use Network Load Balancer
        service.beta.kubernetes.io/aws-load-balancer-internal: "true"  # or "false" for internet
      componentSelector: mysql
      name: mysql-vpc
      serviceName: mysql-vpc
      roleSelector: primary  # [primary, secondary] for MySQL
      spec:
        ipFamilyPolicy: PreferDualStack
        ports:
        - name: mysql
          port: 3306
          protocol: TCP
          targetPort: mysql
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
   kubectl get backuppolicy -n demo -l app.kubernetes.io/instance=mysql-cluster
   ```

2. **View default BackupSchedule**:

   ```bash
   kubectl get backupschedule -n demo -l app.kubernetes.io/instance=mysql-cluster
   ```

#### Full Backup: XtraBackup

using Percona XtraBackup to perform a full backup and  Upload backup file using `datasafed push`

1. **On-Demand Backup**:

   ```bash
   kubectl apply -f examples/mysql/backup.yaml
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

#### Continuous Backup: archive-binlog

The method `archive-binlog` performs continuous backup of binlogs for mysql, usually paired with method `xtrabackup`.It key steps are:

- Flushes binlogs when needed (size or time thresholds)
- Upload binlogs using `wal-g binlog-push`
- Purges expired binlogs

#### Scheduled Backups

Update `BackupSchedule` to schedule enable(`enabled`) backup methods and set the time (`cronExpression`) to your need:

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
spec:
  backupPolicyName: mysql-cluster-mysql-backup-policy
  schedules:
  - backupMethod: xtrabackup
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
  - backupMethod: archive-binlog
    cronExpression: '*/30 * * * *'
    enabled: true   # set to `true` to enable continuous backup
    name: archive-binlog
    retentionPeriod: 8d # by default, retentionPeriod of continuous backup is 1d more than that of a full backup.
```

#### Troubleshooting

- **Backup Stuck**:

  ```bash
  kubectl describe backup <name> -n demo  # describe backup
  kubectl get po -n demo -l app.kubernetes.io/instance=mysql-cluster,dataprotection.kubeblocks.io/backup-policy=mysql-cluster-mysql-backup-policy # get list of pods working for Backups
  kubectl logs -n demo <backup-pod> # check backup pod logs
  ```

### Restore Operations

#### Prerequisites

1. **Backup Verification**:
   - Full Backup must be in `Completed` state
   - Continuous Backup must be in `Completed` or `Running` phase, with a valid `timeRange` in status.

2. **Cluster Resources**:
   - Sufficient CPU/memory for new cluster
   - Available storage capacity
   - Network connectivity between backup repo and new cluster

3. **Credentials**:
   - System account encryption keys

#### Restore from a Full Backup

1. **Identify Backup**:

   ```bash
   kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Full,app.kubernetes.io/instance=mysql-cluster # get the list of full backups
   ```

2. **Prepare Credentials**:

   ```bash
   # Get encrypted system accounts
    kubectl get backup <backupName> -n demo -ojson | jq -r '.metadata.annotations | ."kubeblocks.io/encrypted-system-accounts" | fromjson .mysql | tojson |gsub("\""; "\\\"")'
   ```

3. **Configure Restore**:
   Update `examples/mysql/restore.yaml` with:
   - Backup name and namespace: from step 1
   - Encrypted system accounts: from step 2
   - Target cluster configuration

4. **Execute Restore**:

   ```bash
   kubectl apply -f examples/mysql/restore.yaml
   ```

5. **Monitor Progress**:

   ```bash
   # Watch restore status
   kubectl get restore -n demo -w

   # View detailed logs
   kubectl get cluster -n demo -w
   ```

#### Point-in-time Restore

1. **Identify Continuous Backup**

  Check Continuous Backup info:

  ```bash
  # expect EXACTLY ONE continuous backup
  kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Continuous,app.kubernetes.io/instance=mysql-cluster  # get the list of Continuous backups
  ```

  Check `timeRange`:

  ```bash
  kubectl -n demo get backup <backup-name> -oyaml | yq '.status.timeRange' # get a valid time range.
  ```

  expected output likes:

  ```text
  end: "2025-05-07T09:22:50Z"
  start: "2025-05-07T09:12:47Z"
  ```

  Check the list of Full Backups info:

  ```bash
  # expect one or more Full backups
  kubectl get backup -n demo -l dataprotection.kubeblocks.io/backup-type=Full,app.kubernetes.io/instance=mysql-cluster  # get the list of Full backups
  ```

> [!IMPORTANT]
> Make sure this is a full backup meets the condition:
>
> its stopTime/completionTimestamp must **AFTER** Continuous backup's startTime.
>
> KubeBlocks will automatically pick the latest completed Full backup as the base backup.

2. **Prepare Credentials**:

  ```bash
  # Get encrypted system accounts
  kubectl get backup <backup-name> -n demo -ojson | jq -r '.metadata.annotations | ."kubeblocks.io/encrypted-system-accounts" | fromjson .mysql | tojson |gsub("\""; "\\\"")'
  ```

3. **Configure Restore**:
   Update `examples/pg-cluster/restore-pitr.yaml` with:
   - Backup name and namespace: from step 1
   - Point time: falls in `timeRange` from Step 1
   - Encrypted system accounts: from step 2
   - Target cluster configuration

4. **Execute Restore**:

   ```bash
   kubectl apply -f examples/mysql/restore-pitr.yaml
   ```

5. **Monitor Progress**:

   ```bash
   # Watch restore status
   kubectl get restore -n demo -w

   # View detailed logs
   kubectl get cluster -n demo -w
   ```

> [!NOTE]
> Restored Cluster is not necessary of the same resources/replicas/storage class/storage size as the one restored from.

## Monitoring & Observability

### Prerequisites

1. **Prometheus Operator**: Required for metrics collection
   - Skip if already installed
   - Install via: [Prometheus Operator Guide](../docs/install-prometheus.md)

2. **Access Credentials**: Ensure you have:
   - `kubectl` access to the cluster
   - Grafana admin privileges (for dashboard import)

3. **Cluster created with Exporter enabled**
    - create a MySQL Cluster with exporter running as sidecar (`disableExporter: false`)
    - Skip if already created

### Metrics Collection Setup

#### 1. Configure PodMonitor

1. **Get Exporter Details**:

   ```bash
   kubectl get po -n demo mysql-cluster-mysql-0 -oyaml | yq '.spec.containers[] | select(.name=="mysql-exporter") | .ports'
   ```

  <details open>
  <summary>Expected Output:</summary>

   ```text
   - containerPort: 9104
     name: http-metrics
     protocol: TCP
   ```

  </details>

2. **Verify Metrics Endpoint**:

   ```bash
   kubectl -n demo exec -it pods/mysql-cluster-mysql-0 -- \
     curl -s http://127.0.0.1:9104/metrics | head -n 50
   ```

3. **Apply PodMonitor**:

   ```bash
   kubectl apply -f examples/mysql/pod-monitor.yaml
   ```

#### 2. Grafana Dashboard Setup

1. **Import Dashboard**:
   - URL: [MySQL Dashboard](https://raw.githubusercontent.com/apecloud/kubeblocks-addons/refs/heads/main/addons/mysql/dashboards/mysql.json)

2. **Verification**:
   - Confirm metrics appear in Grafana within 2-5 minutes
   - Check for "UP" status in Prometheus targets

### Troubleshooting

- **No Metrics**: check Prometheus

  ```bash
  kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
  kubectl logs -n monitoring <prometheus-pod-name> -c prometheus
  ```

- **Dashboard Issues**: check indicator labels and dashboards
  - Verify Grafana DataSource points to correct Prometheus instance
  - Check for template variable mismatches

## Cleanup

To permanently delete the cluster and all associated resources:

1. First modify the termination policy to ensure all resources are cleaned up:

```bash
# Set termination policy to WipeOut (deletes all resources including PVCs)
kubectl patch cluster -n demo mysql-cluster \
  -p '{"spec":{"terminationPolicy":"WipeOut"}}' \
  --type="merge"
```

2. Verify the termination policy was updated:

```bash
kubectl get cluster -n demo mysql-cluster -o jsonpath='{.spec.terminationPolicy}'
```

3. Delete the cluster:

```bash
kubectl delete cluster -n demo mysql-cluster
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

### Connecting to MySQL

To connect to the MySQL cluster, you can:

- port forward the MySQL service to your local machine:

```bash
kubectl port-forward svc/mysql-cluster-mysql 3306:3306 -n demo
```

- or expose the MySQL service to the internet, as mentioned in the [Networking](#networking) section.

Then you can connect to the MySQL cluster with the following command:

```bash
mysql -h <endpoint> -P 3306 -u <userName> -p <userPasswd>
```

and credentials can be found in the `secret` resource:

```bash
userName=$(kubectl get secret -n demo mysql-cluster-mysql-account-root -ojsonpath='{.data.username}' | base64 -d)
userPasswd=$(kubectl get secret -n demo mysql-cluster-mysql-account-root -ojsonpath='{.data.password}' | base64 -d)
```

### List of K8s Resources created when creating an MySQL Cluster

To get the full list of associated resources created by KubeBlocks for given cluster:

```bash
kubectl get cmp,its,po -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # cluster and worload
kubectl get backuppolicy,backupschedule,backup -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # data protection resources
kubectl get componentparameter,parameter -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # configuration resources
kubectl get opsrequest -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # opsrequest resources
kubectl get svc,secret,cm,pvc -l app.kubernetes.io/instance=<CLUSTER_NAME> -n demo # k8s native resources
```

## References
