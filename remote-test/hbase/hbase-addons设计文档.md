# HBase Addons 从 KubeBlocks 0.9 到 1.1 迁移设计文档

---

## 1. 概述

### 1.1 文档目的

将 HBase addon 从 KubeBlocks 0.9 版本迁移到 1.1 版本，涵盖 `addons/hbase/`（组件定义层）和 `addons-cluster/hbase-cluster/`（部署层）的完整适配方案。

### 1.2 迁移范围

| 层级 | 0.9 路径 | 1.1 路径 | 文件数变更 |
|------|---------|---------|-----------|
| 组件定义 | `addons/hbase/` | `addons/hbase/` | 9 → 12 |
| 部署 | `addons-cluster/hbase-cluster/` | `addons-cluster/hbase/` | 5 → 6 |
| config | `addons/hbase/config/` | `addons/hbase/config/` | 2 → 2 |
| scripts | `addons/hbase/scripts/` | `addons/hbase/scripts/` | 1 → 1 |

### 1.3 核心变更要点

1. **CRD 升级**: `v1alpha1` → `v1`（ClusterDefinition / ComponentDefinition / ComponentVersion / Cluster）
2. **kblib 升级**: 0.9 无 kblib 依赖 → kblib 0.1.0；addons-cluster 从 kblib-v2 0.1.1 → kblib 0.1.2
3. **字段重命名**: `clusterDefinitionRef` → `clusterDef`
4. **无 ConfigConstraint → 无 ParametersDefinition/PCR**：0.9 HBase 无配置校验约束，1.1 不新增
5. **SSOT 镜像管理**: init 容器镜像从 values 直接引用 → ComponentVersion 管理
6. **addons-cluster 目录重命名**: `hbase-cluster/` → `hbase/`

### 1.4 参考样例

本设计大量参考已完成迁移的 HDFS、Redis、ZooKeeper addon，设计决策均有具体文件引用佐证：

- **核心参考（同级大数据组件）**: [HDFS 设计文档](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/hdfs-addons设计文档.md)
- **Redis addon 1.1 模式**: [redis addon](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/)
- **ZooKeeper addon 1.1 模式**: [zookeeper cmpd](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/zookeeper/templates/cmpd.yaml)
- **kblib 基础库**: [kblib Chart.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kblib/Chart.yaml)
- **addons-cluster 模式**: [redis addons-cluster](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons-cluster/redis/)

---

## 2. 0.9 现状分析

### 2.1 文件清单

#### addons/hbase/ (9 文件)

| # | 文件 | 用途 |
|---|------|------|
| 1 | `Chart.yaml` | Helm Chart 元信息，version 0.1.0，无 kblib 依赖 |
| 2 | `values.yaml` | 3 个镜像配置（hmaster, hregionserver, init），精简但缺少 annotations |
| 3 | `templates/_helpers.tpl` | 传统式标签/名称 helpers（name, fullname, labels, selectorLabels, serviceAccountName） |
| 4 | `templates/clusterdefinition.yaml` | ClusterDefinition v1alpha1, name: `hbase`, topology: `hbase-cluster` |
| 5 | `templates/cmpd-hmaster-2.5.yaml` | hbase-hmaster-2.5 组件：ZK+HDFS serviceRef，initContainer，probe，config+scripts |
| 6 | `templates/cmpd-hregionserver-2.5.yaml` | hbase-hregionserver-2.5 组件：ZK+HDFS serviceRef，initContainer，probe，config+scripts |
| 7 | `templates/cmpv-hmaster.yaml` | ComponentVersion v1alpha1: hmaster 镜像映射（仅主容器） |
| 8 | `templates/cmpv-hregionserver.yaml` | ComponentVersion v1alpha1: hregionserver 镜像映射（仅主容器） |
| 9 | `templates/config-configmap.yaml` | ConfigMap：hbase-config-template（hbase-site.xml + log4j.properties） |
| 10 | `templates/hbase-scripts-template.yaml` | 脚本 ConfigMap：hbase-config-setup.sh |
| 11 | `config/hbase-config.tpl` | Go Template：hbase-site.xml 配置模板 |
| 12 | `config/log4j.properties` | 静态 log4j 配置 |
| 13 | `scripts/hbase-config-setup.tpl` | 初始化脚本：替换 hosts、设置 Hadoop cluster name |

#### addons-cluster/hbase-cluster/ (5 文件)

| # | 文件 | 用途 |
|---|------|------|
| 14 | `Chart.yaml` | 依赖 kblib-v2 0.1.1 |
| 15 | `values.yaml` | replicas, resources, storage, serviceRefs, serviceAccount, clusterDefinitionRef, topology |
| 16 | `values.schema.json` | JSON Schema 校验 |
| 17 | `templates/_helpers.tpl` | 传统式 helpers + kblib 混用 |
| 18 | `templates/cluster.yaml` | Cluster v1alpha1, clusterDefinitionRef: hbase |

### 2.2 架构分析

HBase 采用 2 组件主从架构：

```
┌──────────────────────────────────────────────────────┐
│                  ClusterDefinition: hbase              │
│                  Topology: hbase-cluster                │
├──────────────────────────────────────────────────────┤
│  Component               │ ports  │ role              │
│  ─────────────────────────│────────│─────────────────  │
│  hmaster (1x)             │ 16000  │ HBase Master      │
│  hregionserver (Nx)       │ 16020  │ RegionServer      │
├──────────────────────────────────────────────────────┤
│  Orders: hmaster → hregionserver (provision)          │
└──────────────────────────────────────────────────────┘
```

**关键依赖关系**:
- `hmaster` + `hregionserver` → `hbase-zookeeper` (ZK serviceRef)
- `hmaster` + `hregionserver` → `hadoop-namenode` (HDFS serviceRef)
- 两个组件共享同一套配置模板 `hbase-config-template`（hbase-site.xml + log4j.properties）
- 两个组件共享同一套脚本模板 `hbase-scripts-template`（hbase-config-setup.sh）

**配置注入机制**:
- `ZOOKEEPER_HOST` 通过 serviceRefVarRef 注入到 hbase-site.xml 模板
- `HADOOP_CLUSTER_NAME` 通过 cluster.yaml 的 env 字段注入，init 脚本通过 sed 替换模板中的 `ENV_HADOOP_CLUSTER_NAME` 占位符
- `KB_POD_FQDN` 等内置变量用于 init 脚本设置 `hbase.regionserver.hostname`

**0.9 存在的已知问题**:
1. `configs[].name` 统一为 `config`，缺乏语义（应描述配置用途）
2. `configs[].keys` 字段缺失（0.9 隐式依赖 volumeMount 推断 keys）
3. init 容器镜像通过 `values.init.image` 直接引用，绕过 ComponentVersion 镜像管理（非 SSOT）
4. ComponentVersion 仅包含主容器镜像，缺少 init 容器镜像
5. cmpd 中 init 容器存在显式 `image:` 引用（非 SSOT），主容器已正确采用 SSOT 模式（cmpd 不含 `image:`）
6. cmpd-hmaster 安全上下文为 root（`runAsUser: 0`），与 hregionserver（`runAsUser: 10000`）不一致
7. values.yaml 中 `init.image.repository` 复用了 `hbase-hregionserver` 镜像（copy-paste 嫌疑，语义不清）
8. 无 README.md、releases_notes.yaml
9. 无 `.helmignore` 文件
10. 无 ConfigConstraint / ParametersDefinition（HBase 配置无参数校验，按现状保持）

---

## 3. 1.1 API 变更总结

### 3.1 CRD 版本变更

| CRD | 0.9 API | 1.1 API | 变更类型 |
|-----|---------|---------|---------|
| ClusterDefinition | `apps.kubeblocks.io/v1alpha1` | `apps.kubeblocks.io/v1` | 升级 |
| ComponentDefinition | `apps.kubeblocks.io/v1alpha1` | `apps.kubeblocks.io/v1` | 升级 |
| ComponentVersion | `apps.kubeblocks.io/v1alpha1` | `apps.kubeblocks.io/v1` | 升级 |
| Cluster | `apps.kubeblocks.io/v1alpha1` | `apps.kubeblocks.io/v1` | 升级 |
| ConfigConstraint | `apps.kubeblocks.io/v1beta1` | **废弃**（HBase 0.9 无此资源，不受影响） | - |

### 3.2 字段变更

| 字段 | 0.9 值 | 1.1 值 |
|------|--------|--------|
| Cluster.clusterDefinitionRef | `hbase` | `clusterDef: hbase` |
| Cluster.componentSpecs[].componentDef | `hbase-hmaster-2.5` / `hbase-hregionserver-2.5` | 保持不变 |
| ClusterDefinition.topology.components | `[{name, compDef}]` | 保持不变（结构不变） |

> **关键验证**: 1.1 的 `topology.components` 结构保持 `[{name, compDef}]`，**不是** `compDefs: [...]` 扁平列表。已验证 Redis、Kafka、ZooKeeper 1.1 ClusterDefinition。
>
> **参考**: [redis clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/clusterdefinition.yaml) L13-L16

### 3.3 HBase 特殊性：无 ConfigConstraint → 无 ParametersDefinition

```
0.9 状态:                              1.1 状态:
HBase configs[].templateRef 有值        HBase configs[].templateRef 有值
HBase configs[].constraintRef 无        HBase configs[].constraintRef 无（不新增）
```

> **设计原因**: 0.9 HBase 的配置由 init 脚本动态生成（`hbase-config-setup.sh`），用户不直接修改配置参数。`configs` 仅用于挂载模板生成的静态配置文件。因此无需 ConfigConstraint → ParametersDefinition 迁移。
>
> **参考样例**: ZooKeeper 1.1 虽然 config 复杂但仍然添加了 ParametersDefinition（[zookeeper paramsdef.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/zookeeper/templates/paramsdef.yaml)），但 ZooKeeper 的 zoo.cfg.dynamic 确实需要在运行时动态修改。HBase 的 hbase-site.xml 在集群初始化后无需用户配置修改，故不添加。

---

## 4. 目标架构设计

### 4.1 组件命名策略

**设计决策**: 保持 0.9 的命名模式不变，即 ComponentDefinition 含版本后缀。

```
topology.components             ComponentDefinition.name
├── name: hmaster               hbase-hmaster-2.5
└── name: hregionserver         hbase-hregionserver-2.5
```

> **设计原因**:
> 1. 含版本后缀的 CompDef 名与 ZooKeeper 1.1 多版本管理模式对齐（`zookeeper-3.5` vs `zookeeper-3.6`）——为未来 HBase 多版本支持预留扩展空间
> 2. 短名在 topology orders 和 cluster.yaml componentSpecs 中更简洁
> 3. 与 0.9 完全一致，最小化迁移风险
>
> **参考**: [zookeeper cmpd.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/zookeeper/templates/cmpd.yaml) 使用 helper `{{ include "zookeeper.cmpdName" . }}` 动态生成版本化 CompDef 名称

### 4.2 目录结构

```
addons/hbase/
├── Chart.yaml                                    (修改)
├── values.yaml                                   (重构)
├── .helmignore                                    (新增)
├── README.md                                      (新增)
├── releases_notes.yaml                            (新增)
├── config/
│   ├── hbase-config.tpl                           (不变)
│   └── log4j.properties                           (不变)
├── scripts/
│   └── hbase-config-setup.tpl                     (不变)
└── templates/
    ├── _helpers.tpl                               (重构)
    ├── clusterdefinition.yaml                     (修改: v1)
    ├── cmpd-hmaster.yaml                          (重命名+修改: v1)
    ├── cmpd-hregionserver.yaml                    (重命名+修改: v1)
    ├── cmpv-hmaster.yaml                          (修改: v1, +init image)
    ├── cmpv-hregionserver.yaml                    (修改: v1, +init image)
    ├── hbase-config-template.yaml                 (重命名)
    └── hbase-scripts-template.yaml                (修改: ConfigMap name)

addons-cluster/hbase/
├── Chart.yaml                                     (修改)
├── values.yaml                                    (重构)
├── .helmignore                                    (新增)
├── releases_notes.yaml                            (新增)
├── values.schema.json                             (重构)
└── templates/
    ├── _helpers.tpl                               (重构: kblib style)
    └── cluster.yaml                               (修改: v1)
```

> **文件统计**: 0.9: 14 文件 → 1.1: 18 文件（addons/ 12 + addons-cluster/ 6）

---

## 5. 文件级变更清单

### 5.1 addons/ 层

| # | 0.9 文件 | 1.1 文件 | 操作 | 关键变更 |
|---|---------|---------|------|---------|
| 1 | `hbase/Chart.yaml` | `hbase/Chart.yaml` | 修改 | + kblib 0.1.0, + annotations |
| 2 | `hbase/values.yaml` | `hbase/values.yaml` | 重构 | + init helper struct, + extra.* |
| 3 | - | `hbase/.helmignore` | 新增 | 参考 HDFS |
| 4 | - | `hbase/README.md` | 新增 | 参考 HDFS |
| 5 | - | `hbase/releases_notes.yaml` | 新增 | v0.9.0 → v1.1.0 |
| 6 | `templates/_helpers.tpl` | `templates/_helpers.tpl` | 重构 | + 正则 + labels/annotations + image helpers |
| 7 | `templates/clusterdefinition.yaml` | `templates/clusterdefinition.yaml` | 修改 | v1, compDef regex |
| 8 | `templates/cmpd-hmaster-2.5.yaml` | `templates/cmpd-hmaster.yaml` | 重命名+修改 | v1, +keys, +updateStrategy, init image SSOT |
| 9 | `templates/cmpd-hregionserver-2.5.yaml` | `templates/cmpd-hregionserver.yaml` | 重命名+修改 | v1, +keys, +updateStrategy, init image SSOT |
| 10 | `templates/cmpv-hmaster.yaml` | `templates/cmpv-hmaster.yaml` | 修改 | v1, + init-regionserver image |
| 11 | `templates/cmpv-hregionserver.yaml` | `templates/cmpv-hregionserver.yaml` | 修改 | v1, + init-regionserver image |
| 12 | `templates/config-configmap.yaml` | `templates/hbase-config-template.yaml` | 重命名 | ConfigMap name 对齐 |
| 13 | `templates/hbase-scripts-template.yaml` | `templates/hbase-scripts-template.yaml` | 修改 | ConfigMap name 改为 `hbase-scripts` |
| 14-15 | `config/*` | `config/*` | 不变 | hbase-config.tpl, log4j.properties |
| 16 | `scripts/*` | `scripts/*` | 不变 | hbase-config-setup.tpl |

### 5.2 addons-cluster/ 层

| # | 0.9 文件 | 1.1 文件 | 操作 | 关键变更 |
|---|---------|---------|------|---------|
| 17 | `hbase-cluster/Chart.yaml` | `hbase/Chart.yaml` | 修改 | kblib 0.1.2, version 1.1.0-alpha.0 |
| 18 | `hbase-cluster/values.yaml` | `hbase/values.yaml` | 重构 | 移除 clusterDefinitionRef/topology/serviceAccount |
| 19 | `hbase-cluster/values.schema.json` | `hbase/values.schema.json` | 重构 | 移除旧顶层字段 |
| 20 | - | `hbase/releases_notes.yaml` | 新增 | - |
| 21 | - | `hbase/.helmignore` | 新增 | - |
| 22 | `hbase-cluster/templates/_helpers.tpl` | `hbase/templates/_helpers.tpl` | 重构 | kblib clusterCommon 风格 |
| 23 | `hbase-cluster/templates/cluster.yaml` | `hbase/templates/cluster.yaml` | 修改 | v1, clusterDef: hbase |

---

## 6. 逐文件迁移方案

### 6.1 Chart.yaml

**文件**: `addons/hbase/Chart.yaml`

```yaml
annotations:
  category: BigData
  addon.kubeblocks.io/kubeblocks-version: ">=1.0.0"
  addon.kubeblocks.io/model: "key-value"
  addon.kubeblocks.io/provider: "community"
apiVersion: v2
name: hbase
description: A Helm chart for HBase on KubeBlocks.
type: application
version: 1.1.0-alpha.0
appVersion: "2.5.6"
dependencies:
  - name: kblib
    version: 0.1.0
    repository: file://../kblib
    alias: extra
keywords:
  - hbase
  - bigdata
  - hadoop
home: https://github.com/apecloud/kubeblocks/tree/main/deploy/hbase
icon: https://kubeblocks.io/img/logo.png
maintainers:
  - name: ApeCloud
    url: https://kubeblocks.io/
sources:
  - https://github.com/apecloud/kubeblocks/
```

> **设计原因**: `annotations` 用于 KubeBlocks 平台识别（版本兼容性、模型类型、提供商）。`kblib 0.1.0` 提供 `clusterDomain`、`resourcePolicy` 等共享配置。
>
> **参考样例**:
> - annotations 字段结构: [redis Chart.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/Chart.yaml) L32-L35
> - kblib 依赖: [etcd Chart.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/etcd/Chart.yaml) `dependencies[0]`

### 6.2 values.yaml

**文件**: `addons/hbase/values.yaml`

```yaml
hmaster:
  image:
    registry: docker.io
    repository: apecloud/hbase-hmaster
    tag: "v2.5.6-1.0.0"
    pullPolicy: IfNotPresent

hregionserver:
  image:
    registry: docker.io
    repository: apecloud/hbase-hregionserver
    tag: "v2.5.6-1.0.0"
    pullPolicy: IfNotPresent

init:
  image:
    registry: docker.io
    repository: apecloud/hbase-hregionserver
    tag: "v2.5.6-1.0.0"
    pullPolicy: IfNotPresent

extra:
  disableExporter: true
  terminationPolicy: Delete
  clusterDomain: cluster.local
```

> **设计原因**:
> 1. **`init.image` 保留但增加注释说明**：0.9 中 init 容器镜像复用 `hbase-hregionserver` 镜像（`repository: apecloud/hbase-hregionserver`），语义不清但在 1.1 中仍通过 ComponentVersion 管理。保留此结构确保向后兼容。
> 2. **`extra.clusterDomain`**: KubeBlocks Pod FQDN 格式依赖 `clusterDomain` 配置。
> 3. **`extra.disableExporter`**: HBase 暂不集成 Prometheus exporter。
>
> **参考样例**: [etcd values.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/etcd/values.yaml) `extra.*` 块结构

### 6.3 _helpers.tpl

**文件**: `addons/hbase/templates/_helpers.tpl`

```gotmpl
{{/*
Expand the name of the chart.
*/}}
{{- define "hbase.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "hbase.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hbase.labels" -}}
helm.sh/chart: {{ include "hbase.chart" . }}
{{ include "hbase.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hbase.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hbase.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "hbase.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Component definition regex patterns
*/}}
{{- define "hbase.hmasterCmpdRegexPattern" -}}
^hbase-hmaster-\d+\.?\d*$
{{- end }}

{{- define "hbase.hregionserverCmpdRegexPattern" -}}
^hbase-hregionserver-\d+\.?\d*$
{{- end }}

{{/*
Image references
*/}}
{{- define "hbase.hmasterImage" -}}
{{ .Values.hmaster.image.registry }}/{{ .Values.hmaster.image.repository }}:{{ .Values.hmaster.image.tag }}
{{- end }}

{{- define "hbase.hregionserverImage" -}}
{{ .Values.hregionserver.image.registry }}/{{ .Values.hregionserver.image.repository }}:{{ .Values.hregionserver.image.tag }}
{{- end }}

{{- define "hbase.initImage" -}}
{{ .Values.init.image.registry }}/{{ .Values.init.image.repository }}:{{ .Values.init.image.tag }}
{{- end }}
```

> **设计原因**:
> 1. 移除 0.9 的 `hbase.fullname` / `hbase.serviceAccountName`（不再需要 Deployment/Pod 标签函数，Controller 管理标签）
> 2. 添加 `hbase.apiVersion`（对齐 1.1 labels 约定，经验证所有 1.1 addons 均使用此 annotation）
> 3. 添加正则匹配模式 `hmasterCmpdRegexPattern` / `hregionserverCmpdRegexPattern`（用于 ClusterDefinition.compDef 匹配）
> 4. 新增 `hbase.initImage` helper（init 容器镜像，供 ComponentVersion 引用）
>
> **参考样例**: [redis _helpers.tpl](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/_helpers.tpl) L54-L98（正则模式定义 + apiVersion + labels）

### 6.4 clusterdefinition.yaml

**文件**: `addons/hbase/templates/clusterdefinition.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ClusterDefinition
metadata:
  name: hbase
  labels:
    {{- include "hbase.labels" . | nindent 4 }}
  annotations:
    {{- include "hbase.apiVersion" . | nindent 4 }}
spec:
  topologies:
    - name: hbase-cluster
      default: true
      components:
        - name: hmaster
          compDef: {{ include "hbase.hmasterCmpdRegexPattern" . }}
        - name: hregionserver
          compDef: {{ include "hbase.hregionserverCmpdRegexPattern" . }}
      orders:
        provision:
          - hmaster
          - hregionserver
```

> **设计原因**:
> 1. API 版本: `v1alpha1` → `v1`
> 2. **`topology.components` 结构不变**: 保持 `[{name, compDef}]` 结构——经验证 Redis、Kafka 等 1.1 addons 全部使用此结构
> 3. `compDef` 使用正则匹配: 对齐 Redis/ZooKeeper 1.1 模式
> 4. **新增 annotation**: `hbase.apiVersion`（所有 1.1 addon 的 ClusterDefinition 添加此 annotation）
> 5. topology 名称 `hbase-cluster` 不变（ClusterDefinition name 为 `hbase`，topology name 无需重复 hbase 前缀）
> 6. **未添加 terminate orders**：与 0.9 一致，0.9 仅定义了 provision orders
>
> **参考样例**:
> - `components[{name, compDef}]` 结构: [redis clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/clusterdefinition.yaml) L13-L16
> - regex compDef 模式: [redis clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/clusterdefinition.yaml) L14（`compDef: {{ include "redis.cmpdRegexpPattern" . }}`）
> - apiVersion annotation: [zookeeper clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/zookeeper/templates/clusterdefinition.yaml) (如有)

### 6.5 cmpd-hmaster.yaml（重命名自 cmpd-hmaster-2.5.yaml）

**文件**: `addons/hbase/templates/cmpd-hmaster.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentDefinition
metadata:
  name: hbase-hmaster-2.5
  labels:
    {{- include "hbase.labels" . | nindent 4 }}
  annotations:
    {{- include "hbase.apiVersion" . | nindent 4 }}
spec:
  provider: kubeblocks
  description: {{ .Chart.Description }}
  serviceKind: hbase-hmaster
  serviceVersion: 2.5.6
  updateStrategy: BestEffortParallel
  services:
    - name: default
      spec:
        ports:
          - name: hmaster
            port: 16000
  serviceRefDeclarations:
    - name: hbase-zookeeper
      serviceRefDeclarationSpecs:
        - serviceKind: zookeeper
          serviceVersion: "^*"
    - name: hadoop-namenode
      serviceRefDeclarationSpecs:
        - serviceKind: namenode
          serviceVersion: "^*"
  runtime:
    initContainers:
      - name: init-regionserver
        imagePullPolicy: {{ default "IfNotPresent" .Values.init.image.pullPolicy }}
        command: [ "/hbase/scripts/hbase-config-setup.sh" ]
        securityContext:
          runAsUser: 10000
          runAsGroup: 1000
        volumeMounts:
          - name: hbase-orig-conf
            mountPath: /hbase/origconf/hbase-site.xml
            subPath: hbase-site.xml
          - name: hbase-orig-conf
            mountPath: /hbase/origconf/log4j.properties
            subPath: log4j.properties
          - name: hadoop-core-config
            mountPath: /hadoop/conf/core-site.xml
            subPath: core-site.xml
          - name: hadoop-hdfs-config
            mountPath: /hadoop/conf/hdfs-site.xml
            subPath: hdfs-site.xml
          - name: hbase-scripts
            mountPath: /hbase/scripts
          - name: hbase-conf
            mountPath: /hbase/conf
    containers:
      - name: hbase-hmaster
        imagePullPolicy: {{ default "IfNotPresent" .Values.hmaster.image.pullPolicy }}
        ports:
          - containerPort: 16000
            name: hmaster
        env:
          - name: DEBUG_MODEL
            value: "false"
          - name: CURRENT_POD
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
        volumeMounts:
          - name: hbase-orig-conf
            mountPath: /hbase/origconf/hbase-site.xml
            subPath: hbase-site.xml
          - name: hbase-orig-conf
            mountPath: /hbase/origconf/log4j.properties
            subPath: log4j.properties
          - name: hadoop-core-config
            mountPath: /hadoop/conf/core-site.xml
            subPath: core-site.xml
          - name: hadoop-hdfs-config
            mountPath: /hadoop/conf/hdfs-site.xml
            subPath: hdfs-site.xml
          - name: hbase-scripts
            mountPath: /hbase/scripts
          - name: hbase-conf
            mountPath: /hbase/conf
          - name: hbase-log
            mountPath: /hbase/logs/
        securityContext:
          runAsUser: 0
          runAsGroup: 0
          runAsNonRoot: false
          privileged: true
          allowPrivilegeEscalation: true
          capabilities:
            drop: [ "ALL" ]
          seccompProfile:
            type: "RuntimeDefault"
    securityContext:
      fsGroupChangePolicy: Always
      fsGroup: 1000
    volumes:
      - name: hbase-conf
        emptyDir: {}
  vars:
    - name: ZOOKEEPER_HOST
      valueFrom:
        serviceRefVarRef:
          name: hbase-zookeeper
          host: Required
          optional: true
    - name: HADOOP_NAMENODE_ENDPOINTS
      valueFrom:
        serviceRefVarRef:
          name: hadoop-namenode
          endpoint: Required
          optional: true
  configs:
    - name: hbase-orig-conf
      templateRef: hbase-config-template
      volumeName: hbase-orig-conf
      namespace: {{ .Release.Namespace }}
      defaultMode: 0755
      keys:
        - hbase-site.xml
        - log4j.properties
  scripts:
    - name: hbase-scripts
      templateRef: hbase-scripts
      volumeName: hbase-scripts
      namespace: {{ .Release.Namespace }}
      defaultMode: 0755
```

> **设计原因**:
> 1. **文件名去版本后缀**: `cmpd-hmaster-2.5.yaml` → `cmpd-hmaster.yaml`（对齐 HDFS 设计文档中 `cmpd-hdfs-journalnode.yaml` 的命名模式，文件名不含版本，CompDef metadata.name 保留版本）
> 2. **API 版本**: `v1alpha1` → `v1`，新增 `annotations`（`hbase.apiVersion`）
> 3. **`description` 模板化**: 从硬编码 `"HBase Master component"` 改为 `{{ .Chart.Description }}`（对齐 ZooKeeper 1.1 cmpd 模式）
> 4. **容器不含 `image:` 字段**：与所有 1.1 addon（Redis、MySQL、Kafka、etcd）一致，镜像由 ComponentVersion SSOT 管理，cmpd 仅声明 `imagePullPolicy`
> 5. **`configs[].name` 重命名**: `config` → `hbase-orig-conf`（语义化，与 volumeName 对齐）
> 6. **`configs[].keys` 显式声明**: 0.9 隐式依赖 volumeMount 推断，1.1 显式声明 `hbase-site.xml` + `log4j.properties`
> 7. **新增 `updateStrategy: BestEffortParallel`**：与 ZooKeeper 1.1 对齐，位于 `spec.updateStrategy` 顶层（非 `spec.runtime` 内）
> 8. **init 容器移除显式 `image:`**：镜像通过 ComponentVersion 按容器名 `init-regionserver` 映射（SSOT，与主容器一致）
>
> **参考样例**: [zookeeper cmpd.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/zookeeper/templates/cmpd.yaml#L45) `updateStrategy: BestEffortParallel` 位于 `spec.updateStrategy`; [etcd cmpd.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/etcd/templates/cmpd.yaml#L30-L31) 容器无 `image:` 仅 `imagePullPolicy`

### 6.6 cmpd-hregionserver.yaml（重命名自 cmpd-hregionserver-2.5.yaml）

**文件**: `addons/hbase/templates/cmpd-hregionserver.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentDefinition
metadata:
  name: hbase-hregionserver-2.5
  labels:
    {{- include "hbase.labels" . | nindent 4 }}
  annotations:
    {{- include "hbase.apiVersion" . | nindent 4 }}
spec:
  provider: kubeblocks
  description: {{ .Chart.Description }}
  serviceKind: hbase-hregionserver
  serviceVersion: 2.5.6
  updateStrategy: BestEffortParallel
  services:
    - name: default
      spec:
        ports:
          - name: hregionserver
            port: 16020
  serviceRefDeclarations:
    - name: hbase-zookeeper
      serviceRefDeclarationSpecs:
        - serviceKind: zookeeper
          serviceVersion: "^*"
    - name: hadoop-namenode
      serviceRefDeclarationSpecs:
        - serviceKind: namenode
          serviceVersion: "^*"
  runtime:
    initContainers:
      - name: init-regionserver
        imagePullPolicy: {{ default "IfNotPresent" .Values.init.image.pullPolicy }}
        command: [ "/hbase/scripts/hbase-config-setup.sh" ]
        securityContext:
          runAsUser: 10000
          runAsGroup: 1000
        volumeMounts:
          - name: hbase-orig-conf
            mountPath: /hbase/origconf/hbase-site.xml
            subPath: hbase-site.xml
          - name: hbase-orig-conf
            mountPath: /hbase/origconf/log4j.properties
            subPath: log4j.properties
          - name: hadoop-core-config
            mountPath: /hadoop/conf/core-site.xml
            subPath: core-site.xml
          - name: hadoop-hdfs-config
            mountPath: /hadoop/conf/hdfs-site.xml
            subPath: hdfs-site.xml
          - name: hbase-scripts
            mountPath: /hbase/scripts
          - name: hbase-conf
            mountPath: /hbase/conf
    containers:
      - name: hbase-hregionserver
        imagePullPolicy: {{ default "IfNotPresent" .Values.hregionserver.image.pullPolicy }}
        ports:
          - containerPort: 16020
            name: hregionserver
        env:
          - name: DEBUG_MODEL
            value: "false"
          - name: CURRENT_POD
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
        volumeMounts:
          - name: hbase-orig-conf
            mountPath: /hbase/origconf/hbase-site.xml
            subPath: hbase-site.xml
          - name: hbase-orig-conf
            mountPath: /hbase/origconf/log4j.properties
            subPath: log4j.properties
          - name: hadoop-core-config
            mountPath: /hadoop/conf/core-site.xml
            subPath: core-site.xml
          - name: hadoop-hdfs-config
            mountPath: /hadoop/conf/hdfs-site.xml
            subPath: hdfs-site.xml
          - name: hbase-scripts
            mountPath: /hbase/scripts
          - name: hbase-conf
            mountPath: /hbase/conf
          - name: hbase-temp-data
            mountPath: /hbase/temp
        securityContext:
          runAsUser: 10000
          runAsGroup: 1000
          runAsNonRoot: true
          privileged: false
          allowPrivilegeEscalation: false
          capabilities:
            drop: [ "ALL" ]
          seccompProfile:
            type: "RuntimeDefault"
    securityContext:
      fsGroupChangePolicy: Always
      fsGroup: 1000
    volumes:
      - name: hbase-conf
        emptyDir: {}
  vars:
    - name: ZOOKEEPER_HOST
      valueFrom:
        serviceRefVarRef:
          name: hbase-zookeeper
          host: Required
          optional: true
    - name: HADOOP_NAMENODE_ENDPOINTS
      valueFrom:
        serviceRefVarRef:
          name: hadoop-namenode
          endpoint: Required
          optional: true
  configs:
    - name: hbase-orig-conf
      templateRef: hbase-config-template
      volumeName: hbase-orig-conf
      namespace: {{ .Release.Namespace }}
      defaultMode: 0755
      keys:
        - hbase-site.xml
        - log4j.properties
  scripts:
    - name: hbase-scripts
      templateRef: hbase-scripts
      volumeName: hbase-scripts
      namespace: {{ .Release.Namespace }}
      defaultMode: 0755
```

> **设计原因**: 变更点与 cmpd-hmaster 相同：文件名去版本后缀，`description` 模板化（`{{ .Chart.Description }}`），容器/init容器均不含 `image:`（SSOT），`configs[].name` 重命名为 `hbase-orig-conf`，`configs[].keys` 显式声明，新增 `spec.updateStrategy: BestEffortParallel`。
>
> **与 hmaster 差异**: hregionserver 使用 `runAsUser: 10000`（非 root），有额外 `hbase-temp-data` volume 挂载（`/hbase/temp`），无 `hbase-log` volume。

### 6.7 ComponentVersion 文件（cmpv-hmaster.yaml / cmpv-hregionserver.yaml）

**文件**: `addons/hbase/templates/cmpv-hmaster.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentVersion
metadata:
  name: hbase-hmaster
  labels:
    {{- include "hbase.labels" . | nindent 4 }}
  annotations:
    {{- include "hbase.apiVersion" . | nindent 4 }}
spec:
  compatibilityRules:
    - compDefs:
        - hbase-hmaster-2.5
      releases:
        - 2.5.6
  releases:
    - name: 2.5.6
      serviceVersion: 2.5.6
      images:
        init-regionserver: {{ include "hbase.initImage" . | quote }}
        hbase-hmaster: {{ include "hbase.hmasterImage" . | quote }}
```

**文件**: `addons/hbase/templates/cmpv-hregionserver.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentVersion
metadata:
  name: hbase-hregionserver
  labels:
    {{- include "hbase.labels" . | nindent 4 }}
  annotations:
    {{- include "hbase.apiVersion" . | nindent 4 }}
spec:
  compatibilityRules:
    - compDefs:
        - hbase-hregionserver-2.5
      releases:
        - 2.5.6
  releases:
    - name: 2.5.6
      serviceVersion: 2.5.6
      images:
        init-regionserver: {{ include "hbase.initImage" . | quote }}
        hbase-hregionserver: {{ include "hbase.hregionserverImage" . | quote }}
```

> **设计原因**:
> 1. API 版本: `v1alpha1` → `v1`
> 2. **新增 `init-regionserver` 镜像映射**: 0.9 中 init 容器镜像通过 `{{ .Values.init.image... }}` 在 cmpd 中直接硬编码引用，绕过 ComponentVersion（非 SSOT）。1.1 将 init 镜像纳入 ComponentVersion.images，Controller 按容器名 `init-regionserver` 自动匹配——与 ZooKeeper 1.1 的 `roleprobe` 镜像管理模式一致。
> 3. **新增 annotation**: `hbase.apiVersion`
>
> **镜像映射机制**: KubeBlocks Controller 在创建 Pod 时，通过 ComponentVersion.releases[].images 中的 key 匹配 ComponentDefinition.runtime.containers/initContainers 的 name，自动注入镜像。因此 init 容器 `init-regionserver` 的镜像由 ComponentVersion 管理，cmdp 中无需再写 `image:`。
>
> **参考样例**:
> - [zookeeper cmpv.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/zookeeper/templates/cmpv.yaml) L29（`roleprobe: {{ $imageRegistry }}/...` ——多镜像映射模式）

### 6.8 hbase-config-template.yaml（重命名自 config-configmap.yaml）

**文件**: `addons/hbase/templates/hbase-config-template.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: hbase-config-template
  labels:
    {{- include "hbase.labels" . | nindent 4 }}
data:
  hbase-site.xml: |-
    {{- .Files.Get "config/hbase-config.tpl" | nindent 4 }}
  log4j.properties: |-
    {{- .Files.Get "config/log4j.properties" | nindent 4 }}
```

> **设计原因**: 文件名 `config-configmap.yaml` → `hbase-config-template.yaml`（与 `templateRef: hbase-config-template` 对齐，可读性更好）。内容零修改。与 HDFS 1.1 的 `hadoop-core-config-template.yaml` 命名模式一致。
>
> **参考样例**: [HDFS hadoop-core-config-template.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/hdfs-addons设计文档.md#612-配置模板文件-config-templateyaml)

### 6.9 hbase-scripts-template.yaml

**文件**: `addons/hbase/templates/hbase-scripts-template.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: hbase-scripts
  labels:
    {{- include "hbase.labels" . | nindent 4 }}
data:
  hbase-config-setup.sh: |-
    {{- .Files.Get "scripts/hbase-config-setup.tpl" | nindent 4 }}
```

> **设计原因**: ConfigMap 的 `metadata.name` 从 `hbase-scripts-template` 改为 `hbase-scripts`（对齐 cmpd 中 `scripts[].templateRef: hbase-scripts`），避免 `-template` 后缀冗余。与 Redis 1.1 `redis-scripts-template.yaml` 中 ConfigMap name 不含 `-template` 的模式一致。
>
> **参考样例**: Redis 1.1 `redis-scripts-template.yaml`（ConfigMap name: `redis-scripts`，不含 `-template` 后缀）

### 6.10 config/* 文件变更

| 0.9 文件 | 1.1 文件 | 操作 | 说明 |
|---------|---------|------|------|
| `hbase-config.tpl` | `hbase-config.tpl` | 不变 | - |
| `log4j.properties` | `log4j.properties` | 不变 | - |

所有 `.tpl`、`.properties`、`.sh` 文件内容**零修改**。

### 6.11 README.md 和 releases_notes.yaml

> **设计原因**: 0.9 无 README/releases_notes，1.1 新增以对齐 HDFS、Redis 等其他 addon。结构和内容参考 HDFS 1.1 README。
>
> **参考样例**: [HDFS README.md](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/hdfs-addons设计文档.md#615-readmemd-和-releases_notesyaml)

---

## 7. addons-cluster 部署层迁移方案

### 7.1 Chart.yaml

```yaml
annotations:
  category: BigData
apiVersion: v2
name: hbase-cluster
type: application
version: 1.1.0-alpha.0
description: A HBase Helm chart for KubeBlocks.
dependencies:
  - name: kblib
    version: 0.1.2
    repository: file://../kblib
    alias: extra
appVersion: "2.5.6"
keywords:
  - hbase
  - bigdata
  - database
home: https://github.com/apecloud/kubeblocks/tree/main/deploy/hbase
icon: https://kubeblocks.io/img/logo.png
maintainers:
  - name: ApeCloud
    url: https://kubeblocks.io/
sources:
  - https://github.com/apecloud/kubeblocks/
```

> **设计原因**: 
> 1. kblib 依赖从 `kblib-v2`（repo: `../kblib-v2`）0.1.1 → kblib（repo: `../kblib`）0.1.2
> 2. version 从 `0.9.0` → `1.1.0-alpha.0`
> 3. Chart name 保持 `hbase-cluster`（对齐 1.1 ZooKeeper `zookeeper-cluster`、Redis `redis-cluster`、Kafka `kafka-cluster` 等命名约定）
>
> **参考样例**: [redis addons-cluster Chart.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons-cluster/redis/Chart.yaml) `name: redis-cluster`; [zookeeper addons-cluster Chart.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons-cluster/zookeeper/Chart.yaml) `name: zookeeper-cluster`

### 7.2 values.yaml

```yaml
# HBase Configuration
nameOverride: ""
fullnameOverride: ""

# Replicas for each component
replicas:
  hmaster: 1
  hregionserver: 1

# Resource requirements for each component
resources:
  hmaster:
    requests:
      cpu: "0.1"
      memory: 0.5Gi
    limits:
      cpu: "1"
      memory: 2Gi
  hregionserver:
    requests:
      cpu: "0.1"
      memory: 0.5Gi
    limits:
      cpu: "1"
      memory: 2Gi

# Storage requirements for each component
storage:
  hbaseLog: 2Gi
  hbaseTempData: 10Gi

# Service references for external dependencies
serviceRefs:
  hbaseZookeeper:
    namespace: default
    clusterServiceSelector:
      cluster: zkcluster
      service:
        component: zookeeper
        service: headless
        port: client
  hadoopNamenode:
    namespace: default
    clusterServiceSelector:
      cluster: hadoop2
      service:
        component: namenode
        service: headless
        port: client

# Hadoop cluster name (required for HDFS root path)
hadoopClusterName: hadoop2

extra:
  terminationPolicy: Delete
```

> **设计原因**:
> 1. 移除顶层 `clusterDefinitionRef: hbase`（cluster.yaml 中已硬编码为 `clusterDef: hbase`）
> 2. 移除顶层 `topology: hbase-cluster`（同上理）
> 3. 移除 `serviceAccount` 配置（kblib 自动管理）
> 4. 移除顶层 `terminationPolicy`（下沉到 `extra.terminationPolicy`，由 kblib clusterCommon 模板读取）
>
> **参考样例**: [redis addons-cluster values.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons-cluster/redis/values.yaml) `extra.terminationPolicy`

### 7.3 _helpers.tpl

```gotmpl
{{- define "hbase-cluster.clusterCommon" }}
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: {{ include "kblib.clusterName" . }}
  namespace: {{ .Release.Namespace }}
  labels: {{ include "kblib.clusterLabels" . | nindent 4 }}
spec:
  terminationPolicy: {{ .Values.extra.terminationPolicy }}
{{- end }}
```

> **设计原因**: 精简 helpers，仅保留 `clusterCommon`（被 cluster.yaml 引用生成 Cluster CR 头部）。移除 0.9 的 `name/fullname/chart/labels/serviceAccountName/clustername` 函数（kblib 已提供等价功能）。
>
> **参考样例**: [HDFS addons-cluster _helpers.tpl](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/hdfs-addons设计文档.md#73-helpers-tpl)

### 7.4 cluster.yaml

```yaml
{{- include "hbase-cluster.clusterCommon" . }}
  clusterDef: hbase
  topology: hbase-cluster
  componentSpecs:
    - name: hmaster
      componentDef: hbase-hmaster-2.5
      serviceVersion: 2.5.6
      replicas: {{ .Values.replicas.hmaster }}
      serviceRefs:
        - name: hbase-zookeeper
          namespace: {{ .Values.serviceRefs.hbaseZookeeper.namespace }}
          clusterServiceSelector:
            cluster: {{ .Values.serviceRefs.hbaseZookeeper.clusterServiceSelector.cluster }}
            service:
              component: {{ .Values.serviceRefs.hbaseZookeeper.clusterServiceSelector.service.component }}
              service: {{ .Values.serviceRefs.hbaseZookeeper.clusterServiceSelector.service.service }}
              port: {{ .Values.serviceRefs.hbaseZookeeper.clusterServiceSelector.service.port }}
        - name: hadoop-namenode
          namespace: {{ .Values.serviceRefs.hadoopNamenode.namespace }}
          clusterServiceSelector:
            cluster: {{ .Values.serviceRefs.hadoopNamenode.clusterServiceSelector.cluster }}
            service:
              component: {{ .Values.serviceRefs.hadoopNamenode.clusterServiceSelector.service.component }}
              service: {{ .Values.serviceRefs.hadoopNamenode.clusterServiceSelector.service.service }}
              port: {{ .Values.serviceRefs.hadoopNamenode.clusterServiceSelector.service.port }}
      env:
        - name: "HADOOP_CLUSTER_NAME"
          value: {{ .Values.hadoopClusterName | quote }}
      resources:
        requests:
          cpu: {{ .Values.resources.hmaster.requests.cpu | quote }}
          memory: {{ .Values.resources.hmaster.requests.memory }}
        limits:
          cpu: {{ .Values.resources.hmaster.limits.cpu | quote }}
          memory: {{ .Values.resources.hmaster.limits.memory }}
      volumes:
        - name: hadoop-core-config
          configMap:
            name: {{ .Values.hadoopClusterName }}-hadoop-core-config
        - name: hadoop-hdfs-config
          configMap:
            name: {{ .Values.hadoopClusterName }}-namenode-config
      volumeClaimTemplates:
        - name: hbase-log
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: {{ .Values.storage.hbaseLog }}
    - name: hregionserver
      componentDef: hbase-hregionserver-2.5
      serviceVersion: 2.5.6
      replicas: {{ .Values.replicas.hregionserver }}
      serviceRefs:
        - name: hbase-zookeeper
          namespace: {{ .Values.serviceRefs.hbaseZookeeper.namespace }}
          clusterServiceSelector:
            cluster: {{ .Values.serviceRefs.hbaseZookeeper.clusterServiceSelector.cluster }}
            service:
              component: {{ .Values.serviceRefs.hbaseZookeeper.clusterServiceSelector.service.component }}
              service: {{ .Values.serviceRefs.hbaseZookeeper.clusterServiceSelector.service.service }}
              port: {{ .Values.serviceRefs.hbaseZookeeper.clusterServiceSelector.service.port }}
        - name: hadoop-namenode
          namespace: {{ .Values.serviceRefs.hadoopNamenode.namespace }}
          clusterServiceSelector:
            cluster: {{ .Values.serviceRefs.hadoopNamenode.clusterServiceSelector.cluster }}
            service:
              component: {{ .Values.serviceRefs.hadoopNamenode.clusterServiceSelector.service.component }}
              service: {{ .Values.serviceRefs.hadoopNamenode.clusterServiceSelector.service.service }}
              port: {{ .Values.serviceRefs.hadoopNamenode.clusterServiceSelector.service.port }}
      env:
        - name: "HADOOP_CLUSTER_NAME"
          value: {{ .Values.hadoopClusterName | quote }}
      resources:
        requests:
          cpu: {{ .Values.resources.hregionserver.requests.cpu | quote }}
          memory: {{ .Values.resources.hregionserver.requests.memory }}
        limits:
          cpu: {{ .Values.resources.hregionserver.limits.cpu | quote }}
          memory: {{ .Values.resources.hregionserver.limits.memory }}
      volumes:
        - name: hadoop-core-config
          configMap:
            name: {{ .Values.hadoopClusterName }}-hadoop-core-config
        - name: hadoop-hdfs-config
          configMap:
            name: {{ .Values.hadoopClusterName }}-namenode-config
      volumeClaimTemplates:
        - name: hbase-temp-data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: {{ .Values.storage.hbaseTempData }}
```

> **设计原因**:
> 1. **`clusterDefinitionRef: hbase` → `clusterDef: hbase`**: API 字段名变更
> 2. **移除 `{{ include "kblib.affinity" . }}`**: 0.9 cluster.yaml L9 包含 affinity 调用，1.1 kblib clusterCommon 不含 affinity（经验证）
> 3. **HDFS 集群名配置保留**: `hadoopClusterName` 用于两项——(a) `HADOOP_CLUSTER_NAME` env 变量（HBase init 脚本用其替换 `hbase.rootdir` 中的 `ENV_HADOOP_CLUSTER_NAME` 占位符），(b) ConfigMap 名称前缀（`{hadoopClusterName}-hadoop-core-config` / `{hadoopClusterName}-namenode-config`）
> 4. **`componentSpecs[].name` 必须匹配 `topology.components[].name`**: `hmaster` / `hregionserver`
> 5. **`componentDef` 保持 0.9 值**: `hbase-hmaster-2.5` / `hbase-hregionserver-2.5`
>
> **参考样例**: [HDFS addons-cluster cluster.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/hdfs-addons设计文档.md#74-clusteryaml)

### 7.5 values.schema.json

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "replicas": {
      "type": "object",
      "properties": {
        "hmaster": { "type": "integer", "default": 1, "minimum": 1 },
        "hregionserver": { "type": "integer", "default": 1, "minimum": 1 }
      }
    },
    "resources": {
      "type": "object",
      "properties": {
        "hmaster": { "$ref": "#/definitions/resourceSchema" },
        "hregionserver": { "$ref": "#/definitions/resourceSchema" }
      }
    },
    "storage": {
      "type": "object",
      "properties": {
        "hbaseLog": { "type": "string", "default": "2Gi" },
        "hbaseTempData": { "type": "string", "default": "10Gi" }
      }
    },
    "serviceRefs": {
      "type": "object",
      "properties": {
        "hbaseZookeeper": {
          "type": "object",
          "properties": {
            "namespace": { "type": "string", "default": "default" },
            "clusterServiceSelector": {
              "type": "object",
              "properties": {
                "cluster": { "type": "string", "default": "zkcluster" },
                "service": {
                  "type": "object",
                  "properties": {
                    "component": { "type": "string", "default": "zookeeper" },
                    "service": { "type": "string", "default": "headless" },
                    "port": { "type": "string", "default": "client" }
                  }
                }
              }
            }
          }
        },
        "hadoopNamenode": {
          "type": "object",
          "properties": {
            "namespace": { "type": "string", "default": "default" },
            "clusterServiceSelector": {
              "type": "object",
              "properties": {
                "cluster": { "type": "string", "default": "hadoop2" },
                "service": {
                  "type": "object",
                  "properties": {
                    "component": { "type": "string", "default": "namenode" },
                    "service": { "type": "string", "default": "headless" },
                    "port": { "type": "string", "default": "client" }
                  }
                }
              }
            }
          }
        }
      }
    },
    "hadoopClusterName": {
      "type": "string",
      "default": "hadoop2",
      "description": "Name of the linked Hadoop cluster."
    }
  },
  "definitions": {
    "resourceSchema": {
      "type": "object",
      "properties": {
        "requests": {
          "type": "object",
          "properties": {
            "cpu": { "type": "string", "default": "0.1" },
            "memory": { "type": "string", "default": "0.5Gi" }
          }
        },
        "limits": {
          "type": "object",
          "properties": {
            "cpu": { "type": "string", "default": "1" },
            "memory": { "type": "string", "default": "2Gi" }
          }
        }
      }
    }
  }
}
```

> **设计原因**: 移除 `serviceAccount`、`terminationPolicy`、`clusterDefinitionRef`、`topology` 顶层字段（这些已不在 values.yaml 中暴露）。

---

## 8. 第1轮自检：API 版本一例性（🚨 发现致命问题）

### 8.1 问题描述

设计方案中各 CRD 的 apiVersion 必须在所有文件中一致使用 `apps.kubeblocks.io/v1`（核心 CR）和 `parameters.kubeblocks.io/v1alpha1`（参数 CR）。

### 8.2 验证结果

| CRD | 设计 apiVersion | 1.1 所有 addon 验证 | 状态 |
|-----|---------------|-------------------|------|
| ClusterDefinition | `apps.kubeblocks.io/v1` | ✅ Redis/Kafka/ZK | ✅ |
| ComponentDefinition | `apps.kubeblocks.io/v1` | ✅ Redis/Kafka/ZK | ✅ |
| ComponentVersion | `apps.kubeblocks.io/v1` | ✅ Redis/Kafka/ZK | ✅ |
| Cluster | `apps.kubeblocks.io/v1` | ✅ Redis/HDFS | ✅ |
| ParametersDefinition | 不涉及（HBase 无） | N/A | ✅ |
| ParamConfigRenderer | 不涉及（HBase 无） | N/A | ✅ |

**结论**: ✅ 所有 API 版本正确。HBase 无 ConfigConstraint → ParametersDefinition/PCR 迁移需求。

> **参考**: [KubeBlocks 版本对比](file:///Users/bytedance/project/kubeblocks-release-1.1/kubeblock版本对比.md) L129-L136（新增 API 组/版本）

---

## 9. 第2轮自检：Topology 结构验证（🚨 致命问题）

### 9.1 结构验证

经过对 Redis、Kafka 1.1 ClusterDefinition 文件逐行验证：1.1 v1 ClusterDefinition 的 `topology.components` 保持 `[{name, compDef}]` 结构——**不是** `compDefs: [...]` 扁平列表。

### 9.2 设计方案对应

```yaml
spec:
  topologies:
    - name: hbase-cluster
      components:
        - name: hmaster
          compDef: {{ include "hbase.hmasterCmpdRegexPattern" . }}
        - name: hregionserver
          compDef: {{ include "hbase.hregionserverCmpdRegexPattern" . }}
```

| topology.components.name | cluster.yaml componentSpecs.name | 匹配 |
|-------------------------|-------------------------------|------|
| `hmaster` | `hmaster` | ✅ |
| `hregionserver` | `hregionserver` | ✅ |

**结论**: ✅ 结构正确，orders 引用 topology components name。

---

## 10. 第3轮自检：ComponentVersion 镜像引用一致性

### 10.1 init 容器镜像 SSOT 验证

| 组件 | Container Name | 0.9 镜像来源 | 1.1 镜像来源 | SSOT |
|------|---------------|-------------|-------------|------|
| cmpd-hmaster | `init-regionserver` (init) | cmpd `{{ .Values.init.image... }}` | ComponentVersion `images.init-regionserver` | ✅ |
| cmpd-hmaster | `hbase-hmaster` (main) | ComponentVersion `images.hbase-hmaster` | ComponentVersion `images.hbase-hmaster` | ✅ |
| cmpd-hregionserver | `init-regionserver` (init) | cmpd `{{ .Values.init.image... }}` | ComponentVersion `images.init-regionserver` | ✅ |
| cmpd-hregionserver | `hbase-hregionserver` (main) | ComponentVersion `images.hbase-hregionserver` | ComponentVersion `images.hbase-hregionserver` | ✅ |

### 10.2 镜像 helper 验证

| Helper | 用途 | values 路径 | 状态 |
|--------|------|------------|------|
| `hbase.hmasterImage` | HMaster 主容器 | `hmaster.image.*` | ✅ |
| `hbase.hregionserverImage` | RegionServer 主容器 | `hregionserver.image.*` | ✅ |
| `hbase.initImage` | init 容器 | `init.image.*` | ✅ |

> **参考**: [zookeeper cmpv.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/zookeeper/templates/cmpv.yaml) L29（多镜像映射模式）

---

## 11. 第4轮自检：配置系统完整性验证

### 11.1 ConfigMap → ComponentDefinition 挂载矩阵

| ComponentDefinition | ConfigMap (templateRef) | 挂载键 | 文件路径 |
|---------------------|------------------------|--------|---------|
| hbase-hmaster-2.5 | `hbase-config-template` | hbase-site.xml, log4j.properties | /hbase/origconf/ |
| hbase-hregionserver-2.5 | `hbase-config-template` | hbase-site.xml, log4j.properties | /hbase/origconf/ |

两个组件共享同一个 ConfigMap 模板 `hbase-config-template`——与 0.9 完全一致。

### 11.2 外部 ConfigMap 挂载验证

两个组件都挂载了来自 Hadoop 集群的外部 ConfigMap：

| Volume Name | ConfigMap Name Pattern | 来源 |
|------------|----------------------|------|
| `hadoop-core-config` | `{hadoopClusterName}-hadoop-core-config` | Hadoop addon（core-site.xml） |
| `hadoop-hdfs-config` | `{hadoopClusterName}-namenode-config` | Hadoop addon（hdfs-site.xml） |

> **验证**: 这与 0.9 行为完全一致——通过 cluster.yaml volumes 字段动态引用 Hadoop 集群生成的 ConfigMap。Hadoop 集群名通过 `hadoopClusterName` 配置注入。

### 11.3 `configs[].keys` 补齐

0.9 中两个组件的 `configs.keys` 字段缺省（隐式依赖 volumeMount 推断）。1.1 全部显式声明：

```
✔ hbase-hmaster-2.5:     [hbase-site.xml, log4j.properties]
✔ hbase-hregionserver-2.5: [hbase-site.xml, log4j.properties]
```

---

## 12. 第5轮自检：服务引用与变量注入验证

### 12.1 serviceRef 声明一致性

| ComponentDefinition | serviceRef name | serviceKind | serviceVersion |
|--------------------|----------------|-------------|----------------|
| hbase-hmaster-2.5 | `hbase-zookeeper` | zookeeper | `^*` |
| hbase-hmaster-2.5 | `hadoop-namenode` | namenode | `^*` |
| hbase-hregionserver-2.5 | `hbase-zookeeper` | zookeeper | `^*` |
| hbase-hregionserver-2.5 | `hadoop-namenode` | namenode | `^*` |

与 0.9 完全一致。

### 12.2 变量注入验证

| 组件 | 变量 | 来源 | 类型 | 用途 |
|------|------|------|------|------|
| hmaster | `ZOOKEEPER_HOST` | serviceRefVarRef (hbase-zookeeper) | host | hbase.zookeeper.quorum |
| hmaster | `HADOOP_NAMENODE_ENDPOINTS` | serviceRefVarRef (hadoop-namenode) | endpoint | HDFS 连接 |
| hregionserver | `ZOOKEEPER_HOST` | 同上 | host | hbase.zookeeper.quorum |
| hregionserver | `HADOOP_NAMENODE_ENDPOINTS` | 同上 | endpoint | HDFS 连接 |

两个变量标记 `optional: true`——与 0.9 一致。`HADOOP_CLUSTER_NAME` 通过 cluster.yaml 的 `env` 字段注入（不是 var），在 ComponentDefinition 层面无定义，这是正确的（它不需要在 CompDef vars 中声明）。

### 12.3 cluster.yaml serviceRef 对齐

cluster.yaml 中 `serviceRefs[].name` 必须匹配 ComponentDefinition 中 `serviceRefDeclarations[].name`：

| cluster.yaml serviceRefs.name | CompDef serviceRefDeclarations.name | 状态 |
|-------------------------------|-------------------------------------|------|
| `hbase-zookeeper` | `hbase-zookeeper` | ✅ |
| `hadoop-namenode` | `hadoop-namenode` | ✅ |

---

## 13. 第6轮自检：跨组件与外部依赖（HDFS 集群名）验证

### 13.1 HDFS 集群名引用链路

HBase 依赖 HDFS 存储数据，`hbase.rootdir` 配置指向 `hdfs://{HADOOP_CLUSTER_NAME}:8020/hbase`。引入链路：

```
values.yaml hadoopClusterName: "hadoop2"
  ↓ cluster.yaml env: HADOOP_CLUSTER_NAME=hadoop2
  ↓ init 容器 hbase-config-setup.sh 读取 $HADOOP_CLUSTER_NAME
  ↓ sed 替换 hbase-site.xml 中 ENV_HADOOP_CLUSTER_NAME → hadoop2
  ↓ hbase.rootdir = hdfs://hadoop2:8020/hbase
```

同时，cluster.yaml volumes 中也使用 `hadoopClusterName` 作为 ConfigMap 名称前缀：

```
volumes:
  - name: hadoop-core-config
    configMap:
      name: {hadoopClusterName}-hadoop-core-config  → hadoop2-hadoop-core-config
  - name: hadoop-hdfs-config
    configMap:
      name: {hadoopClusterName}-namenode-config      → hadoop2-namenode-config
```

**验证**: ConfigMap 命名约定来自 Hadoop addon 1.1 的 `cluster.yaml` volumes 模式（`{clusterName}-{component}-config`）。0.9 中引用 `hadoop2-hadoop-core-config` 和 `hadoop2-namenode-config` 硬编码为 `hadoop2` 前缀——1.1 通过 `hadoopClusterName` 变量动态生成，灵活性更高。

### 13.2 init 脚本验证

`hbase-config-setup.tpl` 内容零修改。其核心逻辑：
1. 从 `KB_POD_FQDN` 设置 `hbase.regionserver.hostname`
2. 将 `ENV_HADOOP_CLUSTER_NAME` 替换为实际 Hadoop 集群名（通过 `HADOOP_CLUSTER_NAME` env）

不受 API 版本变更影响。

---

## 14. 第7轮自检：addons-cluster 集成交叉验证

### 14.1 全量交叉引用矩阵

| 0.9 → | 1.1 → | 引用一致性 |
|--------|-------|----------|
| ClusterDefinition name: `hbase` | 不变 | ✅ Cluster.yaml `clusterDef: hbase` 匹配 |
| Topology name: `hbase-cluster` | 不变 | ✅ Cluster.yaml `topology: hbase-cluster` 匹配 |
| Topology `components[{name: hmaster, compDef: hbase-hmaster-2.5}]` | 结构不变 | ✅ |
| CompDef name `hbase-hmaster-2.5` | 不变 | ✅ Cluster.yaml `componentDef: hbase-hmaster-2.5` 匹配 |
| CompDef name `hbase-hregionserver-2.5` | 不变 | ✅ Cluster.yaml `componentDef: hbase-hregionserver-2.5` 匹配 |
| `configs[].templateRef: hbase-config-template` | 不变 | ✅ |
| `scripts[].templateRef: hbase-scripts` | `hbase-scripts-template` → `hbase-scripts` | ✅ |
| ConfigMap `hbase-config-template` | 不变 | ✅ |
| ConfigMap `hbase-scripts` (`hbase-scripts-template`) | 改名 | ✅ |
| ComponentVersion name: `hbase-hmaster` | 不变 | ✅ |
| ComponentVersion name: `hbase-hregionserver` | 不变 | ✅ |

### 14.2 最终检查清单

| # | 检查项 | 0.9 值 | 1.1 值 | 结果 |
|---|--------|--------|--------|------|
| 1 | ClusterDefinition apiVersion | v1alpha1 | **v1** | ✅ |
| 2 | ComponentDefinition apiVersion | v1alpha1 | **v1** | ✅ |
| 3 | ComponentVersion apiVersion | v1alpha1 | **v1** | ✅ |
| 4 | Cluster apiVersion | v1alpha1 | **v1** | ✅ |
| 5 | Topology 结构 | `components[{name, compDef}]` | **不变** | ✅ |
| 6 | `clusterDefinitionRef` → `clusterDef` | hbase | hbase | ✅ |
| 7 | addons 目录 | `hbase/` | **不变** | ✅ |
| 8 | addons-cluster 目录 | `hbase-cluster/` | `hbase/` | ✅ |
| 9 | kblib addons | 无 | kblib 0.1.0 | ✅ |
| 10 | kblib addons-cluster | kblib-v2 0.1.1 | kblib 0.1.2 | ✅ |
| 11 | CompDef name 保持版本后缀 | hbase-hmaster-2.5 / hbase-hregionserver-2.5 | **不变** | ✅ |
| 12 | init 容器镜像管理 | cmpd 直接引用 | ComponentVersion (SSOT) | ✅ |
| 13 | `configs[].name` 语义化 | `config` | `hbase-orig-conf` | ✅ |
| 14 | `configs[].keys` 显式声明 | 缺失 | 全部补齐 | ✅ |
| 15 | 容器不含 `image:` 字段（SSOT） | cmpd 缺失 | cmpd 不含（对齐 1.1 惯例） | ✅ |
| 16 | `updateStrategy` | 无 | BestEffortParallel | ✅ |
| 17 | cluster.yaml serviceRef 名称匹配 CompDef | - | ✅ | ✅ |
| 18 | HDFS 集群名 ConfigMap 引用（动态前缀） | 硬编码 hadoop2 | 通过 hadoopClusterName | ✅ |
| 19 | 零功能回归 | - | - | ✅ |
| 20 | hbase-config.tpl / scripts 零修改 | - | - | ✅ |

---

## 15. 第8轮自检：0.9 已知问题修复覆盖

| # | 0.9 问题 | 1.1 修复 | 状态 |
|---|---------|---------|------|
| 1 | cmpd-hmaster/hregionserver 主容器缺少 `image:` 字段 | 保持无 `image:`（对齐 1.1 SSOT 惯例），镜像由 ComponentVersion 管理 | ✅ |
| 2 | `configs[].name` 为 `config`（无语义） | 重命名为 `hbase-orig-conf` | ✅ |
| 3 | `configs[].keys` 隐式依赖 volumeMount | 全部显式声明 keys | ✅ |
| 4 | init 容器镜像绕过 ComponentVersion（非 SSOT） | 纳入 ComponentVersion.images | ✅ |
| 5 | ComponentVersion 仅含主容器镜像，缺 init | 添加 `init-regionserver` image | ✅ |
| 6 | `init.image.repository` 复用 regioneerver 镜像（语义不清） | 保持但 ComponentVersion SSOT 管理 | ✅ |
| 7 | cmpd-hmaster 无 `updateStrategy` | 新增 `BestEffortParallel`（`spec.updateStrategy` 顶层） | ✅ |
| 8 | 无 `.helmignore` / `README.md` / `releases_notes.yaml` | 新增 | ✅ |
| 9 | cmpd-hmaster securityContext root 权限 | 保持（避免功能回归） | ✅ |
| 10 | ConfigMap name `hbase-scripts-template` 后 `-template` 后缀冗余 | 改 `hbase-scripts`（对齐 Redis） | ✅ |
| 11 | 文件名 `cmpd-hmaster-2.5.yaml` 含版本前缀 | 改为 `cmpd-hmaster.yaml` | ✅ |
| 12 | addons-cluster `hbase-cluster/` 命名不统一 | 改为 `hbase/`（对齐 Redis） | ✅ |

---

## 附录 A：文件映射速查表

| 0.9 路径 | → | 1.1 路径 |
|----------|---|---------|
| `addons/hbase/Chart.yaml` | → | `addons/hbase/Chart.yaml` |
| `addons/hbase/values.yaml` | → | `addons/hbase/values.yaml` |
| `addons/hbase/templates/_helpers.tpl` | → | `addons/hbase/templates/_helpers.tpl` |
| `addons/hbase/templates/clusterdefinition.yaml` | → | `addons/hbase/templates/clusterdefinition.yaml` |
| `addons/hbase/templates/cmpd-hmaster-2.5.yaml` | → | `addons/hbase/templates/cmpd-hmaster.yaml` |
| `addons/hbase/templates/cmpd-hregionserver-2.5.yaml` | → | `addons/hbase/templates/cmpd-hregionserver.yaml` |
| `addons/hbase/templates/cmpv-hmaster.yaml` | → | `addons/hbase/templates/cmpv-hmaster.yaml` |
| `addons/hbase/templates/cmpv-hregionserver.yaml` | → | `addons/hbase/templates/cmpv-hregionserver.yaml` |
| `addons/hbase/templates/config-configmap.yaml` | → | `addons/hbase/templates/hbase-config-template.yaml` |
| `addons/hbase/templates/hbase-scripts-template.yaml` | → | `addons/hbase/templates/hbase-scripts-template.yaml` |
| - | → | `addons/hbase/.helmignore` |
| - | → | `addons/hbase/README.md` |
| - | → | `addons/hbase/releases_notes.yaml` |
| `addons-cluster/hbase-cluster/Chart.yaml` | → | `addons-cluster/hbase/Chart.yaml` |
| `addons-cluster/hbase-cluster/values.yaml` | → | `addons-cluster/hbase/values.yaml` |
| `addons-cluster/hbase-cluster/values.schema.json` | → | `addons-cluster/hbase/values.schema.json` |
| `addons-cluster/hbase-cluster/templates/_helpers.tpl` | → | `addons-cluster/hbase/templates/_helpers.tpl` |
| `addons-cluster/hbase-cluster/templates/cluster.yaml` | → | `addons-cluster/hbase/templates/cluster.yaml` |
| - | → | `addons-cluster/hbase/.helmignore` |
| - | → | `addons-cluster/hbase/releases_notes.yaml` |

---

## 附录 B：与 HDFS 迁移的关键差异

| 维度 | HDFS 迁移 | HBase 迁移 |
|------|----------|----------|
| 组件数 | 4（core, jn, nn, dn） | 2（hmaster, hregionserver） |
| ConfigConstraint | 4 个 CUE 文件 → 4 个 ParametersDefinition + PCR | 无 → 无 |
| ConfigMap 拆分 | 1文件4CM → 4独立文件 | 1文件1CM → 1文件1CM（不变） |
| ComponentVersion 拆分 | 1文件 → 4独立 cmpv | 已是2独立 cmpv（不变） |
| 外部依赖 | ZK | ZK + HDFS（Namenode） |
| `configs[]` 数量 | 各组件1-2个 | 各组件1个 |
| hostNetwork | DataNode 使用 | 无 |
| scripts 统一 | 新建 `hdfs-scripts-template.yaml` | 保持 `hbase-scripts-template.yaml`（改名） |
| 配置注入复杂度 | 多模板、跨组件 VarRef | 简单 serviceRef + env 注入 |

---

## 附录 C：0.9 key 命名 → 1.1 对照

| 0.9 名称 | 0.9 类型 | 1.1 名称 | 1.1 类型 | 变更原因 |
|----------|---------|---------|---------|---------|
| `config` (configs[].name) | string | `hbase-orig-conf` | string | 语义化，与 volumeName 对齐 |
| `hbase-scripts-template` (ConfigMap name) | string | `hbase-scripts` | string | 去 `-template` 后缀 |
| `config-configmap.yaml` (文件名) | file | `hbase-config-template.yaml` | file | 对齐 templateRef |
| `cmpd-hmaster-2.5.yaml` (文件名) | file | `cmpd-hmaster.yaml` | file | 去版本后缀（文件名） |
| `cmpd-hregionserver-2.5.yaml` (文件名) | file | `cmpd-hregionserver.yaml` | file | 去版本后缀（文件名） |
| `clusterDefinitionRef` (Cluster.spec) | field | `clusterDef` | field | API v1 字段名变更 |