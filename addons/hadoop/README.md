# Hadoop HDFS Addon for KubeBlocks

## Overview

This addon provides Hadoop HDFS support on KubeBlocks, including:

- **HA Cluster Topology**: 3-component architecture (journalnode, namenode, datanode)
- **ZooKeeper Integration**: Automatic failover via ZK service reference
- **Host Network**: DataNode supports hostNetwork for optimal I/O performance
- **Configuration Management**: Dynamic parameter tuning via Parameters API

## Components

| Component | Role | Default Replicas |
|-----------|------|-----------------|
| hdfs-journalnode | HA Journal | 3 |
| hdfs-namenode | NameNode (nn0/nn1) | 2 |
| hdfs-datanode | DataNode (hostNetwork) | 1 |

## Quick Start

```bash
# Install addon
helm install hadoop kubeblocks-addons/hadoop

# Create cluster
helm install mycluster kubeblocks-addons-cluster/hadoop
```

## Requirements

- KubeBlocks >= 1.1.0
- ZooKeeper cluster for HA coordination
