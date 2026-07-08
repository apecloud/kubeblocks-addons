# HBase

[English](./README.md)

本文档介绍 KubeBlocks HBase addon 的结构、拓扑、依赖关系、部署方式以及当前可用的配置入口。

## 概览

当前 HBase addon 提供两种拓扑：

| 拓扑 | 组件 | 存储后端 | 外部依赖 | 说明 |
|------|------|----------|----------|------|
| `cluster` | `hmaster`、`hregionserver` | HDFS | ZooKeeper、HDFS NameNode | 适合真实集群部署 |
| `standalone` | `hbase-standalone` | 本地文件系统 | ZooKeeper | 适合开发、验证和轻量场景 |

当前支持的服务版本：

| 大版本 | 说明 |
|--------|------|
| 2.5 | 2.5.6 |

## Addon 提供的内容

`addons/hbase` 目录当前定义了：

- `ClusterDefinition`：`hbase`
- `ComponentDefinition`：
  - `hbase-hmaster`
  - `hbase-hregionserver`
  - `hbase-standalone`
- 配置模板：
  - `hbase-site.xml`
  - `core-site.xml`
  - `hdfs-site.xml`
  - `hbase-env.sh`
- 运行脚本和镜像映射

`addons-cluster/hbase` 目录提供了一个可直接部署的 cluster chart，并已经暴露出一批部署阶段可配置项，用于：

- HBase 运行参数调优
- HDFS 客户端超时、重试、failover 参数
- ZooKeeper 会话和连接参数
- 安全相关开关

## 前置条件

- Kubernetes >= v1.21
- KubeBlocks >= 1.1 已安装并正常运行
- HBase addon 已安装
- ZooKeeper addon 已启用
- 如果使用 `cluster` 拓扑，还需要 Hadoop HDFS addon 已启用
- 建议准备独立 namespace，例如：

```bash
kubectl create ns demo
```

## 拓扑说明

### Cluster 拓扑

Cluster 拓扑包含：

- `hmaster`
- `hregionserver`
- 外部 ZooKeeper
- 外部 HDFS NameNode 服务引用

对应的 Cluster 配置：

```yaml
spec:
  clusterDef: hbase
  topology: cluster
```

### Standalone 拓扑

Standalone 拓扑包含：

- 单个 `hbase-standalone` 组件
- 本地文件系统 `hbase.rootdir`
- 仅依赖 ZooKeeper serviceRef

对应的 Cluster 配置：

```yaml
spec:
  clusterDef: hbase
  topology: standalone
```

## 监控说明

HBase 当前的监控出口已经切到 `jmx-exporter` sidecar，不再依赖旧的 `metrics2 JmxSink`。

- 旧的 `hadoop-metrics2-hbase.properties` JmxSink 路径已经移除
- `hmaster`、`hregionserver` 和 `hbase-standalone` 现在都会带一个 `jmx-exporter` sidecar
- sidecar 通过本地 loopback 抓取 JVM JMX，并对外暴露 `/metrics`

如果希望组件 Service 上带 Prometheus 发现信息，需要在实际部署的 `Cluster` 里将 `spec.componentSpecs[*].disableExporter=false`。

典型的 `PodMonitor` endpoint 如下：

```yaml
podMetricsEndpoints:
  - path: /metrics
    port: http-metrics
    scheme: http
```

## 快速开始

### 安装 Addon

在仓库根目录执行：

```bash
helm install hbase-addon ./addons/hbase
```

### 使用 Cluster Chart 部署

Cluster 模式：

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

Standalone 模式：

```bash
helm install hbase-standalone ./addons-cluster/hbase \
  -n demo \
  --create-namespace \
  --set topology=standalone \
  --set serviceRefs.hbaseZookeeper.namespace=kubeblocks \
  --set serviceRefs.hbaseZookeeper.clusterServiceSelector.cluster=zk
```

## 原生 Cluster API 示例

### 最小 Cluster 模式示例

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

### 最小 Standalone 模式示例

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

## 配置文件结构

当前 addon 会根据不同拓扑渲染不同配置文件：

| 模板文件 | 最终文件 | 使用组件 | 作用 |
|----------|----------|----------|------|
| `config/hbase-site-cluster.tpl` | `hbase-site.xml` | `hmaster`、`hregionserver` | cluster 模式 HBase 主配置 |
| `config/hbase-site-standalone.tpl` | `hbase-site.xml` | `hbase-standalone` | standalone 模式 HBase 主配置 |
| `config/hdfs-common-site.tpl` | `core-site.xml` | cluster 模式 | Hadoop 通用客户端配置 |
| `config/hdfs-client-site.tpl` | `hdfs-site.xml` | cluster 模式 | HDFS nameservice / failover 客户端配置 |
| `config/hbase-env.sh.tpl` | `hbase-env.sh` | 全部组件 | 运行时环境变量和 JVM 参数 |

## 当前部署阶段配置入口

当前 cluster chart 通过 `addons-cluster/hbase/values.yaml` 暴露部署阶段配置。

### 主要参数分组

| 参数前缀 | 适用范围 | 典型参数 |
|----------|----------|----------|
| `hbase.zk.*` | cluster + standalone | `sessionTimeout`、`maxClientCnxns` |
| `hbase.security.*` | cluster + standalone | `authentication`、`authorization` |
| `hbase.common.*` | cluster + standalone | `clientScannerCaching`、`regionMemstoreFlushSize` |
| `hbase.cluster.*` | cluster | `regionserverHandlerCount`、`masterWaitOnRegionserversTimeout`、`splitlogManagerTimeout` |
| `hbase.standalone.*` | standalone | `regionserverHandlerCount`、`hstoreFlusherCount`、`regionMaxFileSize` |
| `hdfs.fs.*` | cluster | `trashInterval` |
| `hdfs.security.*` | cluster | `authentication`、`authorization` |
| `hdfs.ipc.*` | cluster | `clientConnectionMaxIdleTime`、`clientConnectTimeout`、`pingInterval` |
| `hdfs.client.*` | cluster | `webhdfsEnabled`、`failoverMaxAttempts`、`retryPolicy.*`、`commonRetryPolicy.*` |
| `hdfs.hbaseClient.*` | cluster | `ipcClientConnectTimeout`、`ipcClientConnectMaxRetries` |

### 覆盖示例

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

## 验证与排查

检查生成的 Cluster：

```bash
kubectl get cluster -n demo
kubectl describe cluster -n demo hbase-cluster
```

检查 Pod：

```bash
kubectl get pods -n demo -l app.kubernetes.io/instance=hbase-cluster
```

查看容器内最终渲染出的配置：

```bash
kubectl exec -n demo hbase-cluster-hmaster-0 -- cat /opt/bitnami/hbase/conf/hbase-site.xml
kubectl exec -n demo hbase-cluster-hmaster-0 -- cat /opt/bitnami/hbase/conf/core-site.xml
kubectl exec -n demo hbase-cluster-hmaster-0 -- cat /opt/bitnami/hbase/conf/hdfs-site.xml
```

## 当前限制

- `cluster` 拓扑必须依赖外部 ZooKeeper 和 HDFS NameNode 的 serviceRef。
- 当前这批参数是通过 cluster chart values 和 `configs.variables` 暴露的部署阶段能力。
- HBase addon 目前**还没有**接入标准的 `ParametersDefinition` / `ParamConfigRenderer` / config-constraint 参数重配链路。
- 因此当前这些参数应视为部署阶段参数，而不是统一参数管理入口。

## 删除集群

```bash
kubectl patch cluster -n demo hbase-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"
kubectl delete cluster -n demo hbase-cluster
```
