# HBase

[中文说明](./README.zh-CN.md)

Apache HBase is an open-source, distributed, versioned, column-oriented store modeled after Google's Bigtable. This addon enables HBase deployment and lifecycle management on KubeBlocks.

## Overview

The HBase addon currently provides two topologies:

| Topology | Components | Storage Backend | External Dependencies | Notes |
|----------|------------|-----------------|-----------------------|-------|
| `cluster` | `hmaster`, `hregionserver` | HDFS | ZooKeeper, HDFS NameNode | Recommended for production-like deployments |
| `standalone` | `hbase-standalone` | Local filesystem | ZooKeeper | Good for development and functional verification |

Supported service version:

| Major Version | Description |
|---------------|-------------|
| 2.5 | 2.5.6 |

## What This Addon Contains

The addon package under `addons/hbase` defines:

- `ClusterDefinition` named `hbase`
- component definitions for `hbase-hmaster`, `hbase-hregionserver`, and `hbase-standalone`
- config templates for:
  - `hbase-site.xml`
  - `core-site.xml`
  - `hdfs-site.xml`
  - `hbase-env.sh`
- runtime scripts and image mappings

The deployment chart under `addons-cluster/hbase` provides a ready-to-use Cluster chart with deploy-time configuration knobs for:

- HBase runtime tuning
- HDFS client retry / timeout / failover
- ZooKeeper session and connection settings
- security-related flags

## Prerequisites

- Kubernetes cluster >= v1.21
- KubeBlocks >= 1.1 installed and running
- HBase addon installed
- ZooKeeper addon enabled
- Hadoop HDFS addon enabled if you want to use `cluster` topology
- a dedicated namespace for your test or deployment, for example:

```bash
kubectl create ns demo
```

## Topology Details

### Cluster Topology

Cluster topology uses:

- `hmaster` for master coordination
- `hregionserver` for serving data
- external ZooKeeper for coordination
- external HDFS NameNode service for `hbase.rootdir`

Cluster topology name in `ClusterDefinition`:

```yaml
spec:
  clusterDef: hbase
  topology: cluster
```

### Standalone Topology

Standalone topology uses:

- a single `hbase-standalone` component
- local filesystem for `hbase.rootdir`
- ZooKeeper service reference only

Standalone topology name in `ClusterDefinition`:

```yaml
spec:
  clusterDef: hbase
  topology: standalone
```

## Observability

HBase metrics are now exposed through a `jmx-exporter` sidecar instead of the old `metrics2 JmxSink` path.

- the old `hadoop-metrics2-hbase.properties` JmxSink path has been removed
- `hmaster`, `hregionserver`, and `hbase-standalone` now include a `jmx-exporter` sidecar
- the exporter scrapes local JVM JMX over loopback and exposes `/metrics`

If you want Prometheus discovery metadata on the component service, set `spec.componentSpecs[*].disableExporter=false` in the deployed `Cluster`.

Typical PodMonitor endpoint:

```yaml
podMetricsEndpoints:
  - path: /metrics
    port: http-metrics
    scheme: http
```

## Quick Start

### Install the Addon

From the repository root:

```bash
helm install hbase-addon ./addons/hbase
```

### Deploy with the Cluster Chart

Cluster topology:

```bash
helm install hbase-cluster ./addons-cluster/hbase \
  -n demo \
  --create-namespace \
  --set topology=cluster \
  --set serviceRefs.hbaseZookeeper.namespace=kubeblocks \
  --set serviceRefs.hbaseZookeeper.clusterServiceSelector.cluster=zk \
  --set serviceRefs.hdfsNamenode.namespace=kubeblocks \
  --set serviceRefs.hdfsNamenode.clusterServiceSelector.cluster=hdfs
```

If the external HDFS logical nameservice is different from the selected KubeBlocks cluster name, set it explicitly:

```bash
--set hdfs.nameservice=<logical-nameservice>
```

Standalone topology:

```bash
helm install hbase-standalone ./addons-cluster/hbase \
  -n demo \
  --create-namespace \
  --set topology=standalone \
  --set serviceRefs.hbaseZookeeper.namespace=kubeblocks \
  --set serviceRefs.hbaseZookeeper.clusterServiceSelector.cluster=zk
```

### Smoke Validation

After provisioning the demo releases above, run the minimal readiness and connectivity checks with:

```bash
bash ./hack/verify-hbase-hadoop-smoke.sh \
  --namespace demo \
  --cases hbase-standalone,hbase-cluster
```

Use `--dry-run` to review the command sequence before executing it against a live cluster.

## Raw Cluster Examples

### Minimal Cluster Mode Example

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: hbase-cluster
  namespace: demo
spec:
  terminationPolicy: Delete
  clusterDef: hbase
  topology: cluster
  componentSpecs:
    - name: hmaster
      componentDef: hbase-hmaster-2.5
      serviceVersion: 2.5.6
      replicas: 2
      serviceRefs:
        - name: hbase-zookeeper
          namespace: kubeblocks
          clusterServiceSelector:
            cluster: zk
            service:
              component: zookeeper
              service: headless
              port: client
        - name: hdfs-namenode
          namespace: kubeblocks
          clusterServiceSelector:
            cluster: hdfs
            service:
              component: namenode
              service: headless
              port: fs
    - name: hregionserver
      componentDef: hbase-hregionserver-2.5
      serviceVersion: 2.5.6
      replicas: 2
      serviceRefs:
        - name: hbase-zookeeper
          namespace: kubeblocks
          clusterServiceSelector:
            cluster: zk
            service:
              component: zookeeper
              service: headless
              port: client
        - name: hdfs-namenode
          namespace: kubeblocks
          clusterServiceSelector:
            cluster: hdfs
            service:
              component: namenode
              service: headless
              port: fs
```

### Minimal Standalone Mode Example

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: hbase-standalone
  namespace: demo
spec:
  terminationPolicy: Delete
  clusterDef: hbase
  topology: standalone
  componentSpecs:
    - name: hbase-standalone
      componentDef: hbase-standalone-2.5
      serviceVersion: 2.5.6
      replicas: 1
      serviceRefs:
        - name: hbase-zookeeper
          namespace: kubeblocks
          clusterServiceSelector:
            cluster: zk
            service:
              component: zookeeper
              service: headless
              port: client
```

## Configuration Files

The addon renders different config files for different topologies:

| Source Template | Rendered File | Used By | Purpose |
|----------------|---------------|---------|---------|
| `config/hbase-site-cluster.tpl` | `hbase-site.xml` | `hmaster`, `hregionserver` | Cluster-mode HBase configuration |
| `config/hbase-site-standalone.tpl` | `hbase-site.xml` | `hbase-standalone` | Standalone-mode HBase configuration |
| `config/hdfs-common-site.tpl` | `core-site.xml` | cluster topology | Hadoop common client settings |
| `config/hdfs-client-site.tpl` | `hdfs-site.xml` | cluster topology | HDFS nameservice and failover client settings |
| `config/hbase-env.sh.tpl` | `hbase-env.sh` | all components | runtime environment variables and JVM flags |

## Deploy-Time Configuration Surface

The cluster chart exposes deploy-time values through `addons-cluster/hbase/values.yaml`.

### Main Value Groups

| Value Prefix | Applies To | Example Keys |
|-------------|------------|--------------|
| `hbase.zk.*` | cluster and standalone | `sessionTimeout`, `maxClientCnxns` |
| `hbase.security.*` | cluster and standalone | `authentication`, `authorization` |
| `hbase.common.*` | cluster and standalone | `clientScannerCaching`, `regionMemstoreFlushSize` |
| `hbase.cluster.*` | cluster only | `regionserverHandlerCount`, `masterWaitOnRegionserversTimeout`, `splitlogManagerTimeout` |
| `hbase.standalone.*` | standalone only | `regionserverHandlerCount`, `hstoreFlusherCount`, `regionMaxFileSize` |
| `hdfs.fs.*` | cluster only | `trashInterval` |
| `hdfs.security.*` | cluster only | `authentication`, `authorization` |
| `hdfs.ipc.*` | cluster only | `clientConnectionMaxIdleTime`, `clientConnectTimeout`, `pingInterval` |
| `hdfs.client.*` | cluster only | `webhdfsEnabled`, `failoverMaxAttempts`, `retryPolicy.*`, `commonRetryPolicy.*` |
| `hdfs.hbaseClient.*` | cluster only | `ipcClientConnectTimeout`, `ipcClientConnectMaxRetries` |

### Example Overrides

```yaml
topology: cluster

hbase:
  zk:
    sessionTimeout: 45000
  cluster:
    regionserverHandlerCount: 200
    hstoreFlusherCount: 8
    regionserverStartupRetries: 20

hdfs:
  fs:
    trashInterval: 2880
  client:
    failoverMaxAttempts: 30
    webhdfsEnabled: true
```

## Validation and Operations

Check the generated Cluster:

```bash
kubectl get cluster -n demo
kubectl describe cluster -n demo hbase-cluster
```

Check pods:

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=hbase-cluster
```

Inspect rendered config inside a pod:

```bash
kubectl exec -n demo hbase-cluster-hmaster-0 -- cat /opt/bitnami/hbase/conf/hbase-site.xml
kubectl exec -n demo hbase-cluster-hmaster-0 -- cat /opt/bitnami/hbase/conf/core-site.xml
kubectl exec -n demo hbase-cluster-hmaster-0 -- cat /opt/bitnami/hbase/conf/hdfs-site.xml
```

## Current Limitations

- `cluster` topology requires external ZooKeeper and HDFS NameNode service references.
- Deploy-time configuration is currently exposed through the cluster chart values and `configs.variables`.
- The HBase addon does **not** yet provide the standard `ParametersDefinition` / `ParamConfigRenderer` / config-constraint based parameter reconfiguration chain.
- Most HBase and Hadoop client settings here should be treated as deployment-time settings.

## Delete

```bash
kubectl patch cluster -n demo hbase-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"
kubectl delete cluster -n demo hbase-cluster
```
