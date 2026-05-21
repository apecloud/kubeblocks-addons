# HBase

Apache HBase is an open-source, distributed, versioned, column-oriented store modeled after Google's Bigtable. This addon enables HBase cluster management on KubeBlocks.

## Features In KubeBlocks

### Lifecycle Management

| Topology | Horizontal Scaling | Vertical Scaling | Expand Volume | Restart | Stop/Start |
|----------|--------------------|------------------|---------------|---------|------------|
| hbase-cluster | Yes | Yes | Yes | Yes | Yes |

### Versions

| Major Version | Description |
|---------------|-------------|
| 2.5 | 2.5.6 |

## Prerequisites

- Kubernetes cluster >= v1.21
- KubeBlocks installed and running
- ZooKeeper Addon enabled (HBase depends on ZooKeeper)
- Hadoop HDFS Addon enabled (HBase depends on HDFS Namenode)

## Examples

### Create a HBase Cluster

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: hbase-cluster
  namespace: demo
spec:
  terminationPolicy: Delete
  clusterDef: hbase
  topology: hbase-cluster
  componentSpecs:
    - name: hmaster
      componentDef: hbase-hmaster-2.5
      serviceVersion: 2.5.6
      replicas: 1
      resources:
        requests:
          cpu: "0.1"
          memory: 0.5Gi
        limits:
          cpu: "1"
          memory: 2Gi
      serviceRefs:
        - name: hbase-zookeeper
          namespace: default
          clusterServiceSelector:
            cluster: zkcluster
            service:
              component: zookeeper
              service: headless
              port: client
        - name: hadoop-namenode
          namespace: default
          clusterServiceSelector:
            cluster: hadoop2
            service:
              component: namenode
              service: headless
              port: client
      env:
        - name: HADOOP_CLUSTER_NAME
          value: "hadoop2"
      volumes:
        - name: hadoop-core-config
          configMap:
            name: hadoop2-hadoop-core-config
        - name: hadoop-hdfs-config
          configMap:
            name: hadoop2-namenode-config
      volumeClaimTemplates:
        - name: hbase-log
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 2Gi
    - name: hregionserver
      componentDef: hbase-hregionserver-2.5
      serviceVersion: 2.5.6
      replicas: 1
      resources:
        requests:
          cpu: "0.1"
          memory: 0.5Gi
        limits:
          cpu: "1"
          memory: 2Gi
      serviceRefs:
        - name: hbase-zookeeper
          namespace: default
          clusterServiceSelector:
            cluster: zkcluster
            service:
              component: zookeeper
              service: headless
              port: client
        - name: hadoop-namenode
          namespace: default
          clusterServiceSelector:
            cluster: hadoop2
            service:
              component: namenode
              service: headless
              port: client
      env:
        - name: HADOOP_CLUSTER_NAME
          value: "hadoop2"
      volumes:
        - name: hadoop-core-config
          configMap:
            name: hadoop2-hadoop-core-config
        - name: hadoop-hdfs-config
          configMap:
            name: hadoop2-namenode-config
      volumeClaimTemplates:
        - name: hbase-temp-data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 10Gi
```

```bash
kubectl apply -f examples/hbase/cluster.yaml
```

### Delete

```bash
kubectl patch cluster -n demo hbase-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"
kubectl delete cluster -n demo hbase-cluster
```