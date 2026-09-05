# Hadoop HDFS Addon for KubeBlocks

[English](./README.md)

本文档说明 `addons/hadoop` 当前提供的能力、拓扑结构、参数入口，以及 `addons-cluster/hadoop` 这次新增的部署阶段配置能力。

## 概览

`addons/hadoop` 当前提供：

- `cluster` 拓扑：`journalnode + namenode + datanode`
- `standalone` 拓扑：`namenode + datanode`
- 基于 ZooKeeper 的 HDFS HA failover
- 可配置的 DataNode `hostNetwork`
- Addon 内置的标准参数管理链路：
  - `ParametersDefinition`
  - CUE config constraints
- `addons-cluster/hadoop` 中额外暴露的一批部署阶段可覆盖项

当前支持的服务版本：

| 大版本 | 实际版本 |
|--------|----------|
| 3.3 | 3.3.4 |

## Addon 当前包含的内容

`addons/hadoop` 目录定义了：

- `ClusterDefinition`：`hadoop`
- 组件定义：
  - `hdfs-journalnode`
  - `hdfs-namenode`
  - `hdfs-namenode-standalone`
  - `hdfs-datanode`
  - `hdfs-datanode-standalone`
- 组件版本定义：NameNode、DataNode、JournalNode
- 配置模板：
  - `core-site.xml`
  - `hdfs-site.xml`
  - `hadoop-env.sh`
    - `hdfs-jmx-exporter.yaml`
- NameNode、DataNode、JournalNode、ZKFC 的启动和初始化脚本
- 标准参数管理资源：
  - `paramsdef-hdfs-common.yaml`
  - `paramsdef-hdfs-common-standalone.yaml`
  - `paramsdef-hdfs-namenode.yaml`
  - `paramsdef-hdfs-namenode-standalone.yaml`
  - `paramsdef-hdfs-datanode.yaml`
  - `paramsdef-hdfs-datanode-standalone.yaml`
  - `paramsdef-hdfs-journalnode.yaml`
  - 直接在 `ParametersDefinition` 中声明的 standalone / cluster 模板绑定

`addons-cluster/hadoop` 目录则提供了一个可直接部署的 cluster chart，并通过 `values.yaml` 暴露了一批部署阶段参数。

## 拓扑说明

### Cluster 拓扑

Cluster 模式是默认拓扑，包含：

| 组件 | 角色 | 默认副本数 |
|------|------|------------|
| `journalnode` | HA edits quorum | 3 |
| `namenode` | Active/Standby NameNode 对 | 2 |
| `datanode` | HDFS 数据服务 | 3 |

行为说明：

- 当前 HA 实现是 active/standby 2NN 模型，不是任意多 NameNode 的 observer 模式。
- `hdfs.ha.nameNodeIds` 已支持配置，但 cluster 模式下当前强制要求正好 2 个条目。
- JournalNode 模板能力本身没有写死只能 3 个，但工程上仍建议使用 3 或 5 这类奇数副本。
- DataNode 副本数只是部署默认值，不是 addon 代码硬限制。

### Standalone 拓扑

Standalone 模式包含：

| 组件 | 角色 | 默认副本数 |
|------|------|------------|
| `namenode` | 本地 NameNode | 1 |
| `datanode` | 本地 DataNode | 1 |

该拓扑适合开发、冒烟验证和轻量功能测试。

## 前置条件

- Kubernetes >= v1.21
- KubeBlocks >= 1.1
- Hadoop addon 已安装
- 使用 `cluster` 拓扑时，需要可用的 ZooKeeper 集群
- 建议使用独立 namespace，例如：

```bash
kubectl create ns demo
```

## 配置入口说明

当前仓库里有两类配置入口，需要分清楚。

### 1. Addon 内的标准参数管理链路

`addons/hadoop` 本身已经包含标准 KubeBlocks 参数链路：

- `ParametersDefinition`
- CUE constraints

这些资源定义在：

- `addons/hadoop/templates/paramsdef-*`

在 `release-1.1` 上，当前 KubeBlocks 的参数链路仍然依赖 `ParamConfigRenderer`
来完成组件配置与 `ParametersDefinition` 的绑定。Hadoop addon 采用的是这条兼容路径，
并将 `ParametersDefinition` 收敛到 `release-1.1` 真正支持的字段范围。

因此，README 不能简单理解成“只有静态配置模板”。Addon 自身已经具备标准参数管理能力，覆盖的配置集合包括：

- `hdfs-common-config`
- `namenode-config`
- `datanode-config`
- `journalnode-config`

### 2. Cluster Chart 的部署阶段覆盖入口

除此之外，`addons-cluster/hadoop` 这次新增了一批部署阶段参数，链路是：

`values.yaml -> templates/cluster.yaml -> configs.variables -> runtime config templates`

这层主要用于：

- 环境差异化默认值
- 集群首次部署时的容量和网络参数
- 需要在启动前就确定的 HA / 安全 / 路径类参数

## 本次新增的部署阶段参数面

当前 cluster chart 已经暴露以下第一批参数：

| 参数路径 | 作用 |
|----------|------|
| `hdfs.core.hadoopTmpDir` | `hadoop.tmp.dir` |
| `hdfs.security.authentication` | Hadoop 认证模式 |
| `hdfs.security.authorization` | Hadoop 鉴权开关 |
| `hdfs.client.retryPolicyEnabled` | 客户端重试开关 |
| `hdfs.client.retryPolicySpec` | 客户端重试策略 |
| `hdfs.permissions.superusergroup` | HDFS 超级用户组 |
| `hdfs.ha.nameNodeIds` | HA NameNode ID 列表 |
| `hdfs.ha.fencingSshConnectTimeoutMs` | fencing SSH 超时 |
| `hdfs.namenode.webhdfsEnabled` | WebHDFS 开关 |
| `hdfs.namenode.resourceDuReserved` | NameNode 本地保留磁盘 |
| `hdfs.namenode.haLogRollPeriod` | HA log roll 周期 |
| `hdfs.namenode.haTailEditsPeriod` | HA tail edits 周期 |
| `hdfs.datanode.failedVolumesTolerated` | 容忍坏盘数 |
| `hdfs.datanode.duReserved` | DataNode 保留磁盘 |
| `hdfs.journalnode.enableSync` | JournalNode sync 开关 |
| `hdfs.journalnode.editCacheSizeBytes` | JournalNode edit cache 大小 |
| `hdfs.journalnode.syncIntervalMs` | JournalNode sync 周期 |
| `hdfs.replicationMax` | `dfs.replication.max` |

这些默认值和 schema 定义位于：

- `addons-cluster/hadoop/values.yaml`
- `addons-cluster/hadoop/values.schema.json`

## 配置模板与组件映射

当前 addon 会为不同组件和拓扑渲染不同模板：

| 模板文件 | 最终文件 | 使用组件 | 作用 |
|----------|----------|----------|------|
| `config/core-site.tpl` | `core-site.xml` | cluster 组件 | cluster 模式下的 Hadoop 通用客户端配置 |
| `config/core-site-standalone.tpl` | `core-site.xml` | standalone 组件 | standalone 模式下的 Hadoop 通用客户端配置 |
| `config/hdfs-namenode.tpl` | `hdfs-site.xml` | cluster NameNode | HA NameNode 配置 |
| `config/hdfs-namenode-standalone.tpl` | `hdfs-site.xml` | standalone NameNode | standalone NameNode 配置 |
| `config/hdfs-datanode.tpl` | `hdfs-site.xml` | cluster DataNode | HA 感知的 DataNode 配置 |
| `config/hdfs-datanode-standalone.tpl` | `hdfs-site.xml` | standalone DataNode | standalone DataNode 配置 |
| `config/hdfs-journalnode.tpl` | `hdfs-site.xml` | JournalNode | JournalNode 配置 |
| `config/hadoop-env.sh.tpl` | `hadoop-env.sh` | 全部组件 | 运行时环境变量 |

## 运行时与镜像说明

### DataNode 网络模式

DataNode 当前支持以下网络相关配置：

- `runtime.datanode.hostNetwork`
- `runtime.datanode.hostPID`
- `runtime.datanode.dnsPolicy`

### NameNode 与 initContainer 镜像

默认情况下，NameNode 的 initContainer 复用 NameNode 主镜像；如果有特殊需求，也支持单独覆盖。

相关参数为：

- `nameNode.image.*`
- `nameNode.initImages.initNameNodeFormat.*`
- `nameNode.initImages.initZkfcFormat.*`

这样做既保留了默认路径的简洁性，也支持在必要时做定制镜像切换。

## HA 说明与当前限制

当前 HA 设计是有意收敛的：

- cluster 模式强制要求 `replicas.namenode = 2`
- cluster 模式下 `hdfs.ha.nameNodeIds` 必须正好包含 2 个条目
- NameNode 启动脚本按配置列表顺序解析 peer，而不是依赖固定的 `nn0/nn1` 字面值
- standby bootstrap 已做启动时序保护，避免首次拉起时再次遇到 `OrderedReady` 场景下的 bootstrapStandby 问题

因此，当前能力是“可配置 NameNode ID 的 2NN active/standby 模型”，不是通用 N 个 NameNode 横向扩展模型。

## 监控说明

Hadoop 当前的监控出口已经切到 `jmx-exporter` sidecar，不再依赖旧的 `metrics2 JmxSink`。

- 旧的 `hadoop-metrics2.properties` JmxSink 路径已经移除
- NameNode、DataNode、JournalNode Pod 现在都会带一个 `jmx-exporter` sidecar
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
helm install hadoop-addon ./addons/hadoop
```

### 使用 Cluster Chart 部署

Cluster 模式：

```bash
helm install hdfs-cluster ./addons-cluster/hadoop \
  -n demo \
  --create-namespace \
  --set topology=cluster \
  --set serviceRefs.hadoopZookeeper.namespace=kubeblocks \
  --set serviceRefs.hadoopZookeeper.clusterServiceSelector.cluster=zk
```

Standalone 模式：

```bash
helm install hdfs-standalone ./addons-cluster/hadoop \
  -n demo \
  --create-namespace \
  --set topology=standalone
```

### Smoke 验证

按上面的示例完成部署后，可以执行下面的最小就绪性与连通性验证：

```bash
bash ./hack/verify-hbase-hadoop-smoke.sh \
  --namespace demo \
  --cases hdfs-standalone,hdfs-ha
```

如果只想先审查命令序列，可以追加 `--dry-run`。

### 部署阶段参数覆盖示例

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

## 注意事项

- cluster 模式依赖 ZooKeeper serviceRef
- 当前 HA 实现严格限定为 2NN active/standby
- `addons-cluster/hadoop` 里的 deploy-time values 不是对 addon 标准参数链路的替代，而是一层额外的部署便利入口
- 如果需要按环境切换镜像或 initContainer 镜像，请使用 values 覆盖，不要直接改 vendor 产物
