# Hadoop HDFS Addon for KubeBlocks

[中文说明](./README.zh-CN.md)

This document describes what the Hadoop HDFS addon provides, how it is structured, what configuration surfaces are available today, and what was added recently for deploy-time configuration through the cluster chart.

## Overview

The Hadoop addon under `addons/hadoop` provides HDFS on KubeBlocks with:

- `cluster` topology: `journalnode + namenode + datanode`
- `standalone` topology: `namenode + datanode`
- ZooKeeper-backed HA failover for cluster mode
- configurable DataNode `hostNetwork`
- standard parameter management resources in the addon itself:
  - `ParametersDefinition`
  - `ParamConfigRenderer`
  - CUE config constraints
- an additional deploy-time configuration surface in `addons-cluster/hadoop`

Supported service version:

| Major Version | Actual Version |
|---------------|----------------|
| 3.3 | 3.3.4 |

## What This Addon Contains

The addon package under `addons/hadoop` defines:

- `ClusterDefinition` named `hadoop`
- component definitions for:
  - `hdfs-journalnode`
  - `hdfs-namenode`
  - `hdfs-namenode-standalone`
  - `hdfs-datanode`
  - `hdfs-datanode-standalone`
- component versions for NameNode, DataNode, and JournalNode
- config templates for:
  - `core-site.xml`
  - `hdfs-site.xml`
  - `hadoop-env.sh`
  - `hadoop-metrics2.properties`
- startup and init scripts for NameNode, DataNode, JournalNode, and ZKFC
- parameter management resources:
  - `paramsdef-hdfs-common.yaml`
  - `paramsdef-hdfs-namenode.yaml`
  - `paramsdef-hdfs-datanode.yaml`
  - `paramsdef-hdfs-journalnode.yaml`
  - corresponding `pcr-*` resources

The deployable cluster chart under `addons-cluster/hadoop` provides a ready-to-use `Cluster` manifest and exposes a first batch of deploy-time overrides through `values.yaml`.

## Topologies

### Cluster Topology

Cluster mode is the default topology and contains:

| Component | Role | Default Replicas |
|-----------|------|------------------|
| `journalnode` | quorum journal for HA edits | 3 |
| `namenode` | active/standby NameNode pair | 2 |
| `datanode` | HDFS data service | 3 |

Behavior notes:

- HA is implemented as active/standby NameNode, not arbitrary multi-NN observer mode.
- `hdfs.ha.nameNodeIds` is configurable, but cluster mode currently requires exactly 2 entries.
- JournalNode count is not hard-coded to 3 by template logic, but odd replica counts such as 3 or 5 remain the practical recommendation.
- DataNode count is a deployment default, not an addon hard limit.

### Standalone Topology

Standalone mode contains:

| Component | Role | Default Replicas |
|-----------|------|------------------|
| `namenode` | local NameNode | 1 |
| `datanode` | local DataNode | 1 |

This topology is intended for development, smoke testing, and functional verification.

## Prerequisites

- Kubernetes >= v1.21
- KubeBlocks >= 1.1
- the Hadoop addon installed
- a ZooKeeper cluster available when using `cluster` topology
- a dedicated namespace is recommended, for example:

```bash
kubectl create ns demo
```

## Configuration Surfaces

There are two different configuration surfaces in this repository.

### 1. Standard KubeBlocks Parameter Management in the Addon

The addon itself already contains standard parameter-management artifacts:

- `ParametersDefinition`
- `ParamConfigRenderer`
- CUE constraints

These resources are defined in `addons/hadoop/templates/paramsdef-*` and `addons/hadoop/templates/pcr-*`.

This means the addon is not limited to raw static config templates. The standard KubeBlocks parameter chain already exists for addon-managed configuration files such as:

- `hdfs-common-config`
- `namenode-config`
- `datanode-config`
- `journalnode-config`

### 2. Deploy-Time Overrides in the Cluster Chart

In addition, `addons-cluster/hadoop` now exposes a first batch of deploy-time values that flow through:

`values.yaml -> templates/cluster.yaml -> configs.variables -> runtime config templates`

This deploy-time surface is useful for:

- environment-specific defaults
- cluster bootstrap-time sizing
- HA/network/security knobs that should be set before the cluster starts

## Newly Exposed Deploy-Time Values

The cluster chart now exposes deploy-time overrides for the following groups.

| Value Path | Purpose |
|------------|---------|
| `hdfs.core.hadoopTmpDir` | `hadoop.tmp.dir` |
| `hdfs.security.authentication` | Hadoop auth mode |
| `hdfs.security.authorization` | Hadoop authorization switch |
| `hdfs.client.retryPolicyEnabled` | client retry enablement |
| `hdfs.client.retryPolicySpec` | retry policy spec |
| `hdfs.permissions.superusergroup` | HDFS superuser group |
| `hdfs.ha.nameNodeIds` | configurable HA NameNode IDs |
| `hdfs.ha.fencingSshConnectTimeoutMs` | fencing SSH timeout |
| `hdfs.namenode.webhdfsEnabled` | WebHDFS switch |
| `hdfs.namenode.resourceDuReserved` | NameNode reserved local disk |
| `hdfs.namenode.haLogRollPeriod` | HA log roll period |
| `hdfs.namenode.haTailEditsPeriod` | HA tail edits period |
| `hdfs.datanode.failedVolumesTolerated` | tolerated failed volumes |
| `hdfs.datanode.duReserved` | DataNode reserved disk |
| `hdfs.journalnode.enableSync` | JournalNode sync switch |
| `hdfs.journalnode.editCacheSizeBytes` | JournalNode edit cache size |
| `hdfs.journalnode.syncIntervalMs` | JournalNode sync interval |
| `hdfs.replicationMax` | `dfs.replication.max` |

The deploy-time defaults live in:

- `addons-cluster/hadoop/values.yaml`
- `addons-cluster/hadoop/values.schema.json`

## Config Templates

The addon renders different template files for different components and topologies.

| Source Template | Rendered File | Used By | Purpose |
|----------------|---------------|---------|---------|
| `config/core-site.tpl` | `core-site.xml` | cluster components | common Hadoop client settings for cluster mode |
| `config/core-site-standalone.tpl` | `core-site.xml` | standalone components | common Hadoop client settings for standalone mode |
| `config/hdfs-namenode.tpl` | `hdfs-site.xml` | cluster NameNode | HA NameNode configuration |
| `config/hdfs-namenode-standalone.tpl` | `hdfs-site.xml` | standalone NameNode | standalone NameNode configuration |
| `config/hdfs-datanode.tpl` | `hdfs-site.xml` | cluster DataNode | HA-aware DataNode configuration |
| `config/hdfs-datanode-standalone.tpl` | `hdfs-site.xml` | standalone DataNode | standalone DataNode configuration |
| `config/hdfs-journalnode.tpl` | `hdfs-site.xml` | JournalNode | JournalNode configuration |
| `config/hadoop-env.sh.tpl` | `hadoop-env.sh` | all components | runtime environment variables |

## Runtime and Image Notes

### DataNode Network Mode

DataNode supports runtime network tuning through addon values:

- `runtime.datanode.hostNetwork`
- `runtime.datanode.hostPID`
- `runtime.datanode.dnsPolicy`

### NameNode and Init Container Images

By default, NameNode init containers reuse the NameNode image unless explicitly overridden.

Relevant values:

- `nameNode.image.*`
- `nameNode.initImages.initNameNodeFormat.*`
- `nameNode.initImages.initZkfcFormat.*`

This keeps the default path simple while still allowing custom init-container images when needed.

## HA Notes and Current Limits

Current HA behavior is intentionally conservative:

- cluster topology enforces `replicas.namenode = 2`
- `hdfs.ha.nameNodeIds` must contain exactly 2 entries in cluster mode
- the NameNode startup script maps peer nodes by configured ID order
- standby bootstrap is guarded to avoid the old `OrderedReady` timing problem during initial bring-up

This means the current addon supports configurable NameNode IDs for the existing 2NN active/standby model, not general N-way NameNode scaling.

## Quick Start

### Install the Addon

From the repository root:

```bash
helm install hadoop-addon ./addons/hadoop
```

### Deploy with the Cluster Chart

Cluster mode:

```bash
helm install hdfs-cluster ./addons-cluster/hadoop \
  -n demo \
  --create-namespace \
  --set topology=cluster \
  --set serviceRefs.hadoopZookeeper.namespace=kubeblocks \
  --set serviceRefs.hadoopZookeeper.clusterServiceSelector.cluster=zk
```

Standalone mode:

```bash
helm install hdfs-standalone ./addons-cluster/hadoop \
  -n demo \
  --create-namespace \
  --set topology=standalone
```

### Example Deploy-Time Overrides

```yaml
topology: cluster

replicas:
  journalnode: 3
  namenode: 2
  datanode: 3

hdfs:
  core:
    hadoopTmpDir: /hadoop/tmp
  security:
    authentication: simple
    authorization: false
  ha:
    nameNodeIds: "nn0,nn1"
    fencingSshConnectTimeoutMs: 30000
  namenode:
    webhdfsEnabled: false
    resourceDuReserved: 1073741824
    haLogRollPeriod: 120
    haTailEditsPeriod: 60
  datanode:
    failedVolumesTolerated: 0
    duReserved: 1073741824
  journalnode:
    enableSync: true
    editCacheSizeBytes: 104857600
    syncIntervalMs: 120000
```

## Requirements and Caveats

- cluster mode requires ZooKeeper service references
- current HA implementation is strictly a 2NN active/standby model
- deploy-time values in `addons-cluster/hadoop` are not a replacement for the addon's standard parameter-management resources; they are an additional deployment convenience layer
- if you need environment-specific image layout or custom bootstrap images, use the image override fields instead of patching vendor manifests directly
