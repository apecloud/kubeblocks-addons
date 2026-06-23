# HDFS Addons 从 KubeBlocks 0.9 到 1.1 迁移设计文档

---

## 1. 概述

### 1.1 文档目的

将 HDFS addon 从 KubeBlocks 0.9 版本迁移到 1.1 版本，涵盖 `addons/hadoop-hdfs/`（组件定义层）和 `addons-cluster/hadoop-cluster/`（部署层）的完整适配方案。

### 1.2 迁移范围

| 层级 | 0.9 路径 | 1.1 路径 | 文件数变更 |
|------|---------|---------|-----------|
| 组件定义 | `addons/hadoop-hdfs/` | `addons/hadoop/` | 20 → 29 |
| 部署 | `addons-cluster/hadoop-cluster/` | `addons-cluster/hadoop/` | 5 → 7 |
| config | `addons/hadoop-hdfs/config/` | `addons/hadoop/config/` | 9 → 10 |

### 1.3 核心变更要点

1. **目录重命名**: `hadoop-hdfs` → `hadoop`（对齐 1.1 统一命名规范）
2. **CRD 升级**: `ConfigConstraint` (v1beta1) → `ParametersDefinition` + `ParamConfigRenderer` (v1alpha1)
3. **API 升级**: ClusterDefinition/ComponentDefinition/ComponentVersion/Cluster → `apps.kubeblocks.io/v1`
4. **字段重命名**: `clusterDefinitionRef` → `clusterDef`
5. **kblib 升级**: 移除旧式 helper，采用 kblib 0.1.0/0.1.2 统一依赖

### 1.4 参考样例

本设计大量参考已完成迁移的 Redis、Kafka addon，设计决策均有具体文件引用佐证：
- **核心参考**: [redis addon](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/)
- **ClusterDefinition 模式**: [kafka clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/clusterdefinition.yaml)
- **ParametersDefinition API**: [redis paramsdef-redis.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/paramsdef-redis.yaml)
- **addons-cluster 模式**: [redis 部署层](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons-cluster/redis/)
- **kblib 基础库**: [kblib Chart.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kblib/Chart.yaml)

---

## 2. 0.9 现状分析

### 2.1 文件清单

#### addons/hadoop-hdfs/ (20 文件)

| # | 文件 | 用途 |
|---|------|------|
| 1 | `Chart.yaml` | Helm Chart 元信息，version 0.1.0，无 kblib 依赖 |
| 2 | `values.yaml` | 4 组件镜像配置 + 大量未使用的默认值（replicaCount, ingress 等） |
| 3 | `.helmignore` | Helm 打包忽略规则 |
| 4 | `templates/_helpers.tpl` | 传统式标签/名称 helpers（name, fullname, labels, selectorLabels, serviceAccountName） |
| 5 | `templates/clusterdefinition.yaml` | ClusterDefinition v1alpha1, name: `hadoop-hdfs`, topology: `hadoop-ha-cluster` |
| 6 | `templates/cmpd-hadoop-core.yaml` | hadoop-core 组件：ZK serviceRef，core-site.xml 配置 |
| 7 | `templates/cmpd-journalnode.yaml` | hdfs-journalnode 组件：2 端口，initContainer，probe，config+scripts |
| 8 | `templates/cmpd-namenode.yaml` | hdfs-namenode 组件：2 端口，initContainer，probe，vars+config+scripts |
| 9 | `templates/cmpd-datanode.yaml` | hdfs-datanode 组件：hostNetwork，initContainer，probe，config+scripts |
| 10 | `templates/config-version.yaml` | 4 个 ComponentVersion v1alpha1，含镜像引用（部分硬编码） |
| 11 | `templates/config-constraint.yaml` | 4 个 ConfigConstraint v1beta1，CUE 校验 |
| 12 | `templates/config-configmap.yaml` | 4 个 ConfigMap 配置模板（core-site + log4j + hdfs-site） |
| 13 | `templates/scripts.yaml` | 脚本 ConfigMap（check-journal/name/data-status.sh） |
| 14-17 | `config/core-site.tpl`, `hdfs-*.tpl` | Go Template 配置模板 |
| 18 | `config/log4j.properties` | 日志配置 |
| 19-22 | `config/config-*-constraint.cue` | CUE 参数约束文件 |

#### addons-cluster/hadoop-cluster/ (5 文件)

| # | 文件 | 用途 |
|---|------|------|
| 23 | `Chart.yaml` | 依赖 kblib-v2 0.1.1 |
| 24 | `values.yaml` | replicas, resources, storage, serviceRefs, serviceAccount, clusterDefinitionRef, topology |
| 25 | `values.schema.json` | JSON Schema 校验 |
| 26 | `templates/_helpers.tpl` | 传统式 helpers + kblib 混用 |
| 27 | `templates/cluster.yaml` | Cluster v1alpha1, clusterDefinitionRef: hadoop-hdfs |

### 2.2 架构分析

HDFS 采用 4 组件 HA 架构：

```
┌──────────────────────────────────────────────────────┐
│                  ClusterDefinition: hadoop-hdfs        │
│                  Topology: hadoop-ha-cluster           │
├──────────────────────────────────────────────────────┤
│  Component          │ ports  │ role                  │
│  ──────────────────│────────│─────────────────────   │
│  hadoop-core        │  none  │ 编排层（仅配置生成）     │
│  journalnode (3x)  │ 8485,8480│ HA Journal           │
│  namenode (2x)     │ 8020,9870│ nn0/nn1 HA           │
│  datanode (Nx)     │ 9864+ │ hostNetwork            │
├──────────────────────────────────────────────────────┤
│  Orders: core→jn→nn→dn (provision)                   │
│         dn→nn→jn→core (terminate)                    │
└──────────────────────────────────────────────────────┘
```

**关键依赖关系**:
- `hadoop-core` + `hdfs-namenode` → `hadoopZookeeper` (ZK serviceRef)
- `hdfs-namenode` → `JOURNALNODE_POD_FQDN_LIST` (跨组件 componentVarRef)
- `hdfs-journalnode` → `JOURNALNODE_POD_FQDN_LIST` (自引用 componentVarRef)
- 所有数据组件共享 `hadoop-core-config` ConfigMap (core-site.xml)

**0.9 存在的已知问题**:
1. `configs[].name` 统一为 `config`，缺乏语义
2. `cmpd-journalnode.yaml` 和 `cmpd-namenode.yaml` 的 `constraintRef` 被注释
3. `cmpd-hadoop-core.yaml` 无 `image:` 字段（依赖 Controller 隐式解析）
4. `cmpd-hadoop-core.yaml` 未挂载 `log4j.properties`
5. `config-version.yaml` 中 `hadoop-common` 镜像硬编码为 `apecloud/hadoop-common:v3.3.4`
6. 废弃的 Helm 默认值（livenessProbe, autoscaling, ingress 等）占用 135 行 values.yaml
7. 无 README.md

---

## 3. 1.1 API 变更总结

### 3.1 CRD 版本变更

| CRD | 0.9 API | 1.1 API | 变更类型 |
|-----|---------|---------|---------|
| ClusterDefinition | `apps.kubeblocks.io/v1alpha1` | `apps.kubeblocks.io/v1` | 升级 |
| ComponentDefinition | `apps.kubeblocks.io/v1alpha1` | `apps.kubeblocks.io/v1` | 升级 |
| ComponentVersion | `apps.kubeblocks.io/v1alpha1` | `apps.kubeblocks.io/v1` | 升级 |
| Cluster | `apps.kubeblocks.io/v1alpha1` | `apps.kubeblocks.io/v1` | 升级 |
| ConfigConstraint | `apps.kubeblocks.io/v1beta1` | **废弃** | 替换 |
| ParametersDefinition | 无 | `parameters.kubeblocks.io/v1alpha1` | **新增** |
| ParamConfigRenderer | 无 | `parameters.kubeblocks.io/v1alpha1` | **新增** |

> **关键验证**: ParametersDefinition 和 ParamConfigRenderer 的 apiVersion 是 `parameters.kubeblocks.io/v1alpha1`（而非 `apps.kubeblocks.io`）。
> 已验证 redis、kafka、mysql、zookeeper 1.1 addons，全部使用 `parameters.kubeblocks.io/v1alpha1`。

### 3.2 字段变更

| 字段 | 0.9 值 | 1.1 值 |
|------|--------|--------|
| ClusterDefinition.topology.components | `[{name, compDef}]` | `[{name, compDef}]` (结构不变) |
| Cluster.clusterDefinitionRef | `hadoop-hdfs` | `clusterDef: hadoop` |
| Cluster.componentSpecs[].componentDef | 保持不变 | 保持不变 |

> **关键验证**: 1.1 的 `topology.components` 结构保持 `[{name, compDef}]`，**不是** `compDefs: [...]` 扁平列表。已验证 kafka、mysql、redis 1.1 ClusterDefinition，全部使用 `components: [{name, compDef}]` 结构。
> 
> **参考**: [kafka clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/clusterdefinition.yaml) L13-L16, [mysql clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/mysql/templates/clusterdefinition.yaml)

### 3.3 ConfigConstraint → ParametersDefinition + ParamConfigRenderer

```
0.9                                  1.1
───                                  ───
ConfigConstraint (v1beta1)          
  ├── name                           ParametersDefinition (v1alpha1)
  ├── fileFormatConfig.format=XML  →   ├── metadata.name (同 0.9 name)
  ├── parametersSchema.topLevelKey     ├── spec.fileName (新增：配文件名)
  └── parametersSchema.cue            ├── spec.fileFormatConfig
                                     ├── spec.parametersSchema.topLevelKey
                                     └── spec.parametersSchema.cue

ComponentDefinition.configs[].     ParamConfigRenderer (v1alpha1)
  constraintRef                    →   ├── spec.componentDef (正则匹配)
  templateRef                     →   ├── spec.parametersDefs[] 
                                     └── spec.configs[{name, templateRef}]
```

> **参考**: [redis paramsdef-redis.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/paramsdef-redis.yaml) 和 [redis pcr-redis.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/pcr-redis.yaml)

---

## 4. 目标架构设计

### 4.1 组件命名策略

**设计决策**: 保持 0.9 的命名模式不变，即 topology 中使用短名，compDef 使用 `hdfs-` 前缀全名。

```
topology.components             ComponentDefinition.name
├── name: hadoop-core           hadoop-core
├── name: journalnode           hdfs-journalnode
├── name: namenode              hdfs-namenode
└── name: datanode              hdfs-datanode
```

> **设计原因**: 
> 1. 短名在 topology orders 和 cluster.yaml componentSpecs 中更简洁
> 2. ComponentDefinition name 保持 `hdfs-` 前缀避免与其他 addon 冲突
> 3. 此模式与 0.9 一致，最小化迁移风险
> **参考**: [kafka clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/clusterdefinition.yaml) 同样使用短名（`kafka-combine`）对应长 compDef 名

### 4.2 目录结构

```
addons/hadoop/
├── Chart.yaml
├── values.yaml
├── .helmignore
├── README.md                         (新增)
├── releases_notes.yaml               (新增)
├── config/
│   ├── core-site.tpl
│   ├── hdfs-journalnode.tpl
│   ├── hdfs-namenode.tpl
│   ├── hdfs-datanode.tpl
│   ├── log4j.properties
│   ├── hadoop-core-config-constraint.cue       (重命名)
│   ├── hdfs-journalnode-config-constraint.cue   (重命名)
│   ├── hdfs-namenode-config-constraint.cue     (重命名)
│   └── hdfs-datanode-config-constraint.cue     (重命名)
├── scripts/
│   ├── check-journal-status.sh
│   ├── check-name-status.sh
│   └── check-data-status.sh
└── templates/
    ├── _helpers.tpl
    ├── clusterdefinition.yaml
    ├── cmpd-hadoop-core.yaml
    ├── cmpd-hdfs-journalnode.yaml       (重命名)
    ├── cmpd-hdfs-namenode.yaml           (重命名)
    ├── cmpd-hdfs-datanode.yaml           (重命名)
    ├── cmpv-hadoop-core.yaml             (拆分)
    ├── cmpv-hdfs-journalnode.yaml        (拆分)
    ├── cmpv-hdfs-namenode.yaml           (拆分)
    ├── cmpv-hdfs-datanode.yaml           (拆分)
    ├── paramsdef-hadoop-core.yaml        (替换)
    ├── paramsdef-hdfs-journalnode.yaml   (替换)
    ├── paramsdef-hdfs-namenode.yaml      (替换)
    ├── paramsdef-hdfs-datanode.yaml      (替换)
    ├── pcr-hadoop-core.yaml              (新增)
    ├── pcr-hdfs-journalnode.yaml         (新增)
    ├── pcr-hdfs-namenode.yaml            (新增)
    ├── pcr-hdfs-datanode.yaml            (新增)
    ├── hadoop-core-config-template.yaml  (拆分)
    ├── hdfs-journalnode-config-template.yaml (拆分)
    ├── hdfs-namenode-config-template.yaml    (拆分)
    ├── hdfs-datanode-config-template.yaml    (拆分)
    ├── hdfs-scripts-template.yaml        (新增)
    └── scripts.yaml                      (保留，空)

addons-cluster/hadoop/
├── Chart.yaml
├── values.yaml
├── .helmignore                           (新增)
├── releases_notes.yaml                   (新增)
├── values.schema.json
└── templates/
    ├── _helpers.tpl
    └── cluster.yaml
```

> **文件统计**: 0.9: 25 文件 → 1.1: 36 文件（addons/ 31 + addons-cluster/ 5）

---

## 5. 文件级变更清单

### 5.1 addons/ 层

| # | 0.9 文件 | 1.1 文件 | 操作 | 关键变更 |
|---|---------|---------|------|---------|
| 1 | `hadoop-hdfs/Chart.yaml` | `hadoop/Chart.yaml` | 修改 | + kblib 0.1.0, + annotations |
| 2 | `hadoop-hdfs/values.yaml` | `hadoop/values.yaml` | 重构 | + commonImage, + extra.*, 移除废弃值 |
| 3 | `hadoop-hdfs/.helmignore` | `hadoop/.helmignore` | 不变 | - |
| 4 | - | `hadoop/README.md` | 新增 | 参考 redis README |
| 5 | - | `hadoop/releases_notes.yaml` | 新增 | v0.9.0 → v1.1.0 |
| 6 | `templates/_helpers.tpl` | `templates/_helpers.tpl` | 重构 | + 正则匹配 + labels/annotations 函数 + commonImage helper |
| 7 | `templates/clusterdefinition.yaml` | `templates/clusterdefinition.yaml` | 修改 | v1, components 结构不变 |
| 8 | `templates/cmpd-hadoop-core.yaml` | `templates/cmpd-hadoop-core.yaml` | 修改 | v1, + image, + log4j 挂载 |
| 9 | `templates/cmpd-journalnode.yaml` | `templates/cmpd-hdfs-journalnode.yaml` | 修改 | v1, + keys, 恢复 constraintRef |
| 10 | `templates/cmpd-namenode.yaml` | `templates/cmpd-hdfs-namenode.yaml` | 修改 | v1, + keys, 恢复 constraintRef |
| 11 | `templates/cmpd-datanode.yaml` | `templates/cmpd-hdfs-datanode.yaml` | 修改 | v1, + keys (log4j) |
| 12 | `templates/config-version.yaml` | 拆分为 4 个 cmpv-*.yaml | 拆分 | v1, commonImage helper |
| 13 | `templates/config-constraint.yaml` | 拆分为 4 个 paramsdef-*.yaml | 替换 | ConfigConstraint → ParametersDefinition |
| 14 | - | 4 个 pcr-*.yaml | 新增 | ParamConfigRenderer |
| 15 | `templates/config-configmap.yaml` | 拆分为 4 个 *-config-template.yaml | 拆分 | 独立 ConfigMap |
| 16 | - | `templates/hdfs-scripts-template.yaml` | 新增 | 统一脚本 ConfigMap |
| 17 | `templates/scripts.yaml` | `templates/scripts.yaml` | 保留 | 空（HDFS 无 reload 脚本需求） |
| 18-26 | `config/*` | `config/*` | 重命名 | CUE 文件名对齐 ParametersDefinition |

### 5.2 addons-cluster/ 层

| # | 0.9 文件 | 1.1 文件 | 操作 | 关键变更 |
|---|---------|---------|------|---------|
| 27 | `hadoop-cluster/Chart.yaml` | `hadoop/Chart.yaml` | 修改 | kblib 0.1.2, version 1.1.0-alpha.0 |
| 28 | `hadoop-cluster/values.yaml` | `hadoop/values.yaml` | 重构 | 移除 clusterDefinitionRef/topology/serviceAccount |
| 29 | `hadoop-cluster/values.schema.json` | `hadoop/values.schema.json` | 重构 | 移除旧顶层字段 |
| 30 | - | `hadoop/releases_notes.yaml` | 新增 | - |
| 31 | - | `hadoop/.helmignore` | 新增 | - |
| 32 | `hadoop-cluster/templates/_helpers.tpl` | `hadoop/templates/_helpers.tpl` | 重构 | kblib 风格 |
| 33 | `hadoop-cluster/templates/cluster.yaml` | `hadoop/templates/cluster.yaml` | 修改 | v1, clusterDef: hadoop |

---

## 6. 逐文件迁移方案

### 6.1 Chart.yaml

**文件**: `addons/hadoop/Chart.yaml`

```yaml
annotations:
  category: BigData
  addon.kubeblocks.io/kubeblocks-version: ">=1.0.0"
  addon.kubeblocks.io/model: "key-value"
  addon.kubeblocks.io/provider: "community"
apiVersion: v2
name: hadoop
description: A Helm chart for Hadoop HDFS on KubeBlocks.
type: application
version: 1.1.0-alpha.0
appVersion: "3.3.4"
dependencies:
  - name: kblib
    version: 0.1.0
    repository: file://../kblib
    alias: extra
keywords:
  - hadoop
  - hdfs
  - bigdata
home: https://github.com/apecloud/kubeblocks/tree/main/deploy/hadoop
icon: https://kubeblocks.io/img/logo.png
maintainers:
  - name: ApeCloud
    url: https://kubeblocks.io/
sources:
  - https://github.com/apecloud/kubeblocks/
```

> **设计原因**: `annotations` 用于 KubeBlocks 平台识别（版本兼容性、模型类型、提供商）。`kblib 0.1.0` 提供 `clusterDomain`、`resourcePolicy` 等共享配置。
> **参考样例**: [redis Chart.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/Chart.yaml) L32-L35（annotations 字段结构）。

### 6.2 values.yaml

**文件**: `addons/hadoop/values.yaml`

```yaml
# Hadoop common image (used by initContainers via ComponentVersion.hadoop-common)
image:
  common:
    registry: docker.io
    repository: apecloud/hadoop-common
    tag: "v3.3.4"
    pullPolicy: IfNotPresent

# Component-specific images
core:
  image:
    registry: docker.io
    repository: apecloud/hadoop-common
    tag: "v3.3.4-1.0.0"
    pullPolicy: IfNotPresent

journalNode:
  image:
    registry: docker.io
    repository: apecloud/hdfs-journalnode
    tag: "v3.3.4-1.0.0"
    pullPolicy: IfNotPresent

nameNode:
  image:
    registry: docker.io
    repository: apecloud/hdfs-namenode
    tag: "v3.3.4-1.0.0"
    pullPolicy: IfNotPresent

dataNode:
  image:
    registry: docker.io
    repository: apecloud/hdfs-datanode
    tag: "v3.3.4-1.0.0"
    pullPolicy: IfNotPresent

# kblib 扩展配置
extra:
  disableExporter: true
  terminationPolicy: Delete
  clusterDomain: cluster.local
```

> **设计原因**:
> 1. **新增 `image.common`**: 0.9 中 initContainer 的 `hadoop-common` 镜像在 ComponentVersion 中硬编码为 `apecloud/hadoop-common:v3.3.4`。1.1 新增 `image.common` 配置项，实现"单信源"（SSOT），与组件专用镜像解耦。
> 2. **`core.image.repository` 修正**: 0.9 values.yaml 中 `core.image.repository: apecloud/hdfs-journalnode` 是明显的 copy-paste 错误（hadoop-core 不运行 JournalNode），修正为 `apecloud/hadoop-common`。
> 3. **移除废弃值**: 删除 0.9 中 `replicaCount`、`livenessProbe`、`autoscaling`、`ingress`、`affinity`、`tolerations` 等 60+ 行从未使用的 Helm 默认值。
> 4. **`extra.clusterDomain`**: KubeBlocks Pod FQDN 格式依赖 `clusterDomain` 配置。
> **参考样例**: [redis values.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/values.yaml) `extra.*` 块结构。

### 6.3 _helpers.tpl

**文件**: `addons/hadoop/templates/_helpers.tpl`

```gotmpl
{{/*
Chart name
*/}}
{{- define "hadoop.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart name and version for labels
*/}}
{{- define "hadoop.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hadoop.labels" -}}
helm.sh/chart: {{ include "hadoop.chart" . }}
{{ include "hadoop.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hadoop.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hadoop.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "hadoop.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "hadoop.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "hadoop.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Component definition regex patterns
*/}}
{{- define "hadoop.hadoopCoreCmpdRegexPattern" -}}
^hadoop-core$
{{- end }}

{{- define "hadoop.hdfsJournalnodeCmpdRegexPattern" -}}
^hdfs-journalnode$
{{- end }}

{{- define "hadoop.hdfsNamenodeCmpdRegexPattern" -}}
^hdfs-namenode$
{{- end }}

{{- define "hadoop.hdfsDatanodeCmpdRegexPattern" -}}
^hdfs-datanode$
{{- end }}

{{/*
Image references
*/}}
{{- define "hadoop.commonImage" -}}
{{ .Values.image.common.registry }}/{{ .Values.image.common.repository }}:{{ .Values.image.common.tag }}
{{- end }}

{{- define "hadoop.coreImage" -}}
{{ .Values.core.image.registry }}/{{ .Values.core.image.repository }}:{{ .Values.core.image.tag }}
{{- end }}

{{- define "hadoop.journalNodeImage" -}}
{{ .Values.journalNode.image.registry }}/{{ .Values.journalNode.image.repository }}:{{ .Values.journalNode.image.tag }}
{{- end }}

{{- define "hadoop.nameNodeImage" -}}
{{ .Values.nameNode.image.registry }}/{{ .Values.nameNode.image.repository }}:{{ .Values.nameNode.image.tag }}
{{- end }}

{{- define "hadoop.dataNodeImage" -}}
{{ .Values.dataNode.image.registry }}/{{ .Values.dataNode.image.repository }}:{{ .Values.dataNode.image.tag }}
{{- end }}
```

> **设计原因**:
> 1. 移除 0.9 的 `hadoop-hdfs.name/fullname/selectorLabels/serviceAccountName`（不再需要 Deployment/Pod 标签函数，Controller 管理标签）
> 2. 添加 `hadoop.labels` / `hadoop.apiVersion` / `hadoop.annotations`（对齐 1.1 labels/annotations 约定）。`hadoop.annotations` 聚合 `kblib.helm.resourcePolicy` + `hadoop.apiVersion`，与 kafka 1.1 的 `kafka.annotations` 模式一致。
> 3. 添加正则匹配模式 `cmpdRegexPattern`（用于 ClusterDefinition.topology.components.compDef 和 ComponentVersion.compatibilityRules.compDefs）
> 4. 新增 `hadoop.commonImage` helper（initContainer 通用 Hadoop 镜像，独立于组件镜像）
> **参考样例**: [redis _helpers.tpl](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/_helpers.tpl) L54-L98（正则模式定义 + apiVersion + labels），[kafka _helpers.tpl](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/_helpers.tpl) L56-L66（annotations 模板 + componentDefName 与 cmpdRegexpPattern 分离）

### 6.4 clusterdefinition.yaml

**文件**: `addons/hadoop/templates/clusterdefinition.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ClusterDefinition
metadata:
  name: hadoop
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.apiVersion" . | nindent 4 }}
spec:
  topologies:
    - name: ha-cluster
      default: true
      components:
        - name: hadoop-core
          compDef: {{ include "hadoop.hadoopCoreCmpdRegexPattern" . }}
        - name: journalnode
          compDef: {{ include "hadoop.hdfsJournalnodeCmpdRegexPattern" . }}
        - name: namenode
          compDef: {{ include "hadoop.hdfsNamenodeCmpdRegexPattern" . }}
        - name: datanode
          compDef: {{ include "hadoop.hdfsDatanodeCmpdRegexPattern" . }}
      orders:
        provision:
          - hadoop-core
          - journalnode
          - namenode
          - datanode
        terminate:
          - datanode
          - namenode
          - journalnode
          - hadoop-core
```

> **设计原因**:
> 1. API 版本: `v1alpha1` → `v1`
> 2. **`topology.components` 结构不变**: 保持 `[{name, compDef}]` 结构——经验证 kafka、mysql、redis 等 1.1 addons 全部使用此结构。
> 3. `compDef` 使用正则匹配: 对齐 redis/kafka 1.1 模式，使 ParamConfigRenderer 通过正则绑定 ComponentDefinition
> 4. **orders 引用 component name**（`journalnode`），而非 compDef name（`hdfs-journalnode`）
> 5. topology 名称: `hadoop-ha-cluster` → `ha-cluster`（ClusterDefinition 上下文中 `hadoop-` 冗余）
> 6. 标签改为 `hadoop.labels` + `hadoop.apiVersion` annotation
> **参考样例**:
> - `components[{name, compDef}]` 结构: [kafka clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/clusterdefinition.yaml) L13-L16
> - orders 用法: [kafka clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/clusterdefinition.yaml) L18-L24
> - regex compDef 模式: [redis clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/clusterdefinition.yaml) L14（`compDef: {{ include "redis.cmpdRegexpPattern" . }}`）

### 6.5 cmpd-hadoop-core.yaml

**文件**: `addons/hadoop/templates/cmpd-hadoop-core.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentDefinition
metadata:
  name: hadoop-core
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.apiVersion" . | nindent 4 }}
spec:
  provider: kubeblocks
  description: {{ .Chart.Description }}
  serviceKind: hadoop-core
  serviceRefDeclarations:
    - name: hadoopZookeeper
      serviceRefDeclarationSpecs:
        - serviceKind: zookeeper
          serviceVersion: "^*"
  runtime:
    containers:
      - name: hadoop-core
        image: {{ include "hadoop.coreImage" . | quote }}
        imagePullPolicy: {{ .Values.core.image.pullPolicy }}
        env:
          - name: DEBUG_MODEL
            value: "false"
        volumeMounts:
          - name: hadoop-core-config
            mountPath: /hadoop/conf/core-site.xml
            subPath: core-site.xml
          - name: hadoop-core-config
            mountPath: /hadoop/conf/log4j.properties
            subPath: log4j.properties
    securityContext:
      runAsGroup: 0
      runAsNonRoot: true
      runAsUser: 10000
  updateStrategy: BestEffortParallel
  vars:
    - name: ZOOKEEPER_ENDPOINTS
      valueFrom:
        serviceRefVarRef:
          name: hadoopZookeeper
          endpoint: Required
  configs:
    - name: hadoop-core-config
      templateRef: hadoop-core-config-template
      constraintRef: hadoop-core-config-constraints
      volumeName: hadoop-core-config
      namespace: {{ .Release.Namespace }}
      defaultMode: 0755
      keys:
        - core-site.xml
```

> **设计原因**:
> 1. **新增 `image:` 字段**: 0.9 中 hadoop-core 容器缺少 `image:`（仅 `imagePullPolicy:`），依赖 Controller 隐式解析 ComponentVersion。1.1 显式引用 image helper，提高可维护性。
> 2. **新增 `log4j.properties` 挂载**: 0.9 ConfigMap `hadoop-core-config-template` 包含 `log4j.properties`，但 cmpd-hadoop-core 未挂载（遗漏）。1.1 补全挂载。
> 3. **`configs[].keys`**: 显式声明 `core-site.xml`。`log4j.properties` 是静态文件无需 Go Template 渲染，通过 ConfigMap 数据直接提供（与 0.9 datanode 模式一致）
> 4. **移除 scripts 引用**：hadoop-core 是编排组件，不需要健康检查脚本
> **参考样例**: [kafka cmpd](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/) 服务引用声明模式。

### 6.6 cmpd-hdfs-journalnode.yaml

**文件**: `addons/hadoop/templates/cmpd-hdfs-journalnode.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentDefinition
metadata:
  name: hdfs-journalnode
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.apiVersion" . | nindent 4 }}
spec:
  provider: kubeblocks
  description: {{ .Chart.Description }}
  serviceKind: hdfs-journalnode
  services:
    - name: default
      spec:
        ports:
          - name: jn
            port: 8485
          - name: http
            port: 8480
  runtime:
    initContainers:
      - name: hadoop-common
        imagePullPolicy: IfNotPresent
        command:
          - /bin/bash
        args:
          - -ec
          - |
            cp -r /opt/software/hadoop-3.3.4/* /opt/kubeemr/hadoop/hadoop-3.3.4
            mkdir -p /hadoop/dfs/journal
            chown -R 10000:1000 /hadoop/dfs/journal
            chown -R 10000:1000 /opt/kubeemr/hadoop/hadoop-3.3.4
        securityContext:
          runAsUser: 0
        volumeMounts:
          - name: hadoop-common
            mountPath: /opt/kubeemr/hadoop/hadoop-3.3.4
          - name: edits-dir
            mountPath: /hadoop/dfs/journal
            subPath: journal
    containers:
      - name: hdfs-journalnode
        image: {{ include "hadoop.journalNodeImage" . | quote }}
        imagePullPolicy: {{ .Values.journalNode.image.pullPolicy }}
        ports:
          - containerPort: 8485
            name: jn
          - containerPort: 8480
            name: http
        env:
          - name: DEBUG_MODEL
            value: "false"
          - name: WAIT_ZK_TO_READY
            value: "false"
        livenessProbe:
          failureThreshold: 6
          initialDelaySeconds: 30
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 5
          exec:
            command:
              - /bin/bash
              - /kubeblocks/scripts/check-journal-status.sh
        readinessProbe:
          failureThreshold: 6
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 5
          exec:
            command:
              - /bin/bash
              - /kubeblocks/scripts/check-journal-status.sh
        volumeMounts:
          - name: hadoop-common
            mountPath: /opt/kubeemr/hadoop/hadoop-3.3.4
          - name: edits-dir
            mountPath: /hadoop/dfs/journal
            subPath: journal
          - name: hadoop-core-config
            mountPath: /hadoop/conf/core-site.xml
            subPath: core-site.xml
          - name: journalnode-config
            mountPath: /hadoop/conf/hdfs-site.xml
            subPath: hdfs-site.xml
          - name: journalnode-config
            mountPath: /hadoop/conf/log4j.properties
            subPath: log4j.properties
          - name: scripts
            mountPath: /kubeblocks/scripts
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
      - name: hadoop-common
        emptyDir: {}
  updateStrategy: BestEffortParallel
  vars:
    - name: JOURNALNODE_POD_FQDN_LIST
      valueFrom:
        componentVarRef:
          optional: false
          podFQDNs: Required
  configs:
    - name: journalnode-config
      templateRef: journalnode-config-template
      constraintRef: journalnode-config-constraints
      volumeName: journalnode-config
      namespace: {{ .Release.Namespace }}
      defaultMode: 0755
      keys:
        - hdfs-site.xml
  scripts:
    - name: hadoop-scripts
      templateRef: hadoop-scripts
      volumeName: scripts
      namespace: {{ .Release.Namespace }}
      defaultMode: 0755
```

> **设计原因**:
> 1. **单一 configs 条目**：只有 `journalnode-config`（组件专用 hdfs-site.xml）。共享的 `hadoop-core-config`（core-site.xml）由 hadoop-core 组件独立生成，通过 cluster.yaml 的 `volumes[].configMap` 共享挂载到所有数据组件——与 0.9 行为完全一致。
> 2. **`constraintRef` 恢复**: 0.9 中被注释 `# constraintRef: journalnode-config-constraints`，1.1 恢复（参数校验在 ComponentDefinition 层面仍有效）
> 3. **`configs[].keys` 显式声明**: `[hdfs-site.xml]`——log4j.properties 是静态文件无需 Go Template 渲染，由 ConfigMap 数据直接提供
> 4. **scripts 使用统一 ConfigMap**：模板引用 `hadoop-scripts`（由 `hdfs-scripts-template.yaml` 生成）
> **参考样例**: [redis cmpd-redis-sentinel.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/cmpd-redis-sentinel.yaml) 单 configs + scripts 模式。

### 6.7 cmpd-hdfs-namenode.yaml

**文件**: `addons/hadoop/templates/cmpd-hdfs-namenode.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentDefinition
metadata:
  name: hdfs-namenode
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.apiVersion" . | nindent 4 }}
spec:
  provider: kubeblocks
  description: {{ .Chart.Description }}
  serviceKind: hdfs-namenode
  services:
    - name: default
      spec:
        ports:
          - name: fs
            port: 8020
          - name: http
            port: 9870
  serviceRefDeclarations:
    - name: hadoopZookeeper
      serviceRefDeclarationSpecs:
        - serviceKind: zookeeper
          serviceVersion: "^*"
  runtime:
    initContainers:
      - name: hadoop-common
        imagePullPolicy: IfNotPresent
        securityContext:
          runAsUser: 0
        command:
          - /bin/bash
        args:
          - -ec
          - |
            cp -r /opt/software/hadoop-3.3.4/* /opt/kubeemr/hadoop/hadoop-3.3.4
            mkdir -p /hadoop/dfs/metadata
            mkdir -p /hadoop/dfs/journal
            chown -R 10000:1000 /hadoop
            chown -R 10000:1000 /opt/kubeemr/hadoop/hadoop-3.3.4
        volumeMounts:
          - name: hadoop-common
            mountPath: /opt/kubeemr/hadoop/hadoop-3.3.4
          - name: metadata-dir
            mountPath: /hadoop
    containers:
      - name: hdfs-namenode
        image: {{ include "hadoop.nameNodeImage" . | quote }}
        imagePullPolicy: {{ .Values.nameNode.image.pullPolicy }}
        ports:
          - containerPort: 8020
            name: fs
          - containerPort: 9870
            name: http
        env:
          - name: DEBUG_MODEL
            value: "false"
          - name: CURRENT_POD
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
        livenessProbe:
          failureThreshold: 6
          initialDelaySeconds: 30
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 5
          exec:
            command:
              - /bin/bash
              - /kubeblocks/scripts/check-name-status.sh
        readinessProbe:
          failureThreshold: 6
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 5
          exec:
            command:
              - /bin/bash
              - /kubeblocks/scripts/check-name-status.sh
        volumeMounts:
          - name: hadoop-common
            mountPath: /opt/kubeemr/hadoop/hadoop-3.3.4
          - name: metadata-dir
            mountPath: /hadoop
          - name: hadoop-core-config
            mountPath: /hadoop/conf/core-site.xml
            subPath: core-site.xml
          - name: namenode-config
            mountPath: /hadoop/conf/hdfs-site.xml
            subPath: hdfs-site.xml
          - name: namenode-config
            mountPath: /hadoop/conf/log4j.properties
            subPath: log4j.properties
          - name: scripts
            mountPath: /kubeblocks/scripts
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
      - name: hadoop-common
        emptyDir: {}
  updateStrategy: BestEffortParallel
  vars:
    - name: JOURNALNODE_POD_FQDN_LIST
      valueFrom:
        componentVarRef:
          compDef: hdfs-journalnode
          optional: false
          podFQDNs: Required
    - name: ZOOKEEPER_ENDPOINTS
      valueFrom:
        serviceRefVarRef:
          name: hadoopZookeeper
          endpoint: Required
  configs:
    - name: namenode-config
      templateRef: namenode-config-template
      constraintRef: namenode-config-constraints
      volumeName: namenode-config
      namespace: {{ .Release.Namespace }}
      defaultMode: 0755
      keys:
        - hdfs-site.xml
  scripts:
    - name: hadoop-scripts
      templateRef: hadoop-scripts
      volumeName: scripts
      namespace: {{ .Release.Namespace }}
      defaultMode: 0755
```

> **设计原因**:
> 1. 单一 configs 条目（`namenode-config`），共享 `hadoop-core-config` 通过 cluster.yaml volumes 挂载——与 0.9 和 journalnode 保持一致
> 2. `JOURNALNODE_POD_FQDN_LIST` 的 `compDef: hdfs-journalnode` 不变——NameNode 需要 JournalNode FQDN 配置 `dfs.namenode.shared.edits.dir`
> 3. `constraintRef` 恢复: 与 journalnode 一致，恢复 0.9 中被注释的校验引用
> 4. `configs[].keys: [hdfs-site.xml]`——仅需模板渲染的配置项
> **关键差异说明**: journalnode 的 `componentVarRef` 不指定 `compDef`（自身引用），namenode 指定 `compDef: hdfs-journalnode`（跨组件引用）——两者行为正确且不同。

### 6.8 cmpd-hdfs-datanode.yaml

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentDefinition
metadata:
  name: hdfs-datanode
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.apiVersion" . | nindent 4 }}
spec:
  provider: kubeblocks
  description: {{ .Chart.Description }}
  serviceKind: hdfs-datanode
  runtime:
    hostNetwork: true
    hostPID: true
    dnsPolicy: ClusterFirstWithHostNet
    initContainers:
      - name: hadoop-common
        imagePullPolicy: IfNotPresent
        command:
          - /bin/bash
        args:
          - -ec
          - |
            cp -r /opt/software/hadoop-3.3.4/* /opt/kubeemr/hadoop/hadoop-3.3.4
            mkdir -p /hadoop/dfs/data0
            chown -R 10000:1000 /opt/kubeemr/hadoop/hadoop-3.3.4
            chown -R 10000:1000 /hadoop/dfs/data0
        securityContext:
          runAsUser: 0
        volumeMounts:
          - name: hadoop-common
            mountPath: /opt/kubeemr/hadoop/hadoop-3.3.4
          - name: hdfs-data-0
            mountPath: /hadoop/dfs/data0
            subPath: data0
    containers:
      - name: hdfs-datanode
        image: {{ include "hadoop.dataNodeImage" . | quote }}
        imagePullPolicy: {{ .Values.dataNode.image.pullPolicy }}
        env:
          - name: DEBUG_MODEL
            value: "false"
        livenessProbe:
          failureThreshold: 6
          initialDelaySeconds: 30
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 5
          exec:
            command:
              - /bin/bash
              - /kubeblocks/scripts/check-data-status.sh
        readinessProbe:
          failureThreshold: 6
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 5
          exec:
            command:
              - /bin/bash
              - /kubeblocks/scripts/check-data-status.sh
        volumeMounts:
          - name: hadoop-common
            mountPath: /opt/kubeemr/hadoop/hadoop-3.3.4
          - name: hadoop-core-config
            mountPath: /hadoop/conf/core-site.xml
            subPath: core-site.xml
          - name: datanode-config
            mountPath: /hadoop/conf/hdfs-site.xml
            subPath: hdfs-site.xml
          - name: datanode-config
            mountPath: /hadoop/conf/log4j.properties
            subPath: log4j.properties
          - name: hdfs-data-0
            mountPath: /hadoop/dfs/data0
            subPath: data0
          - name: scripts
            mountPath: /kubeblocks/scripts
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
      - name: hadoop-common
        emptyDir: {}
  updateStrategy: BestEffortParallel
  configs:
    - name: datanode-config
      templateRef: datanode-config-template
      constraintRef: datanode-config-constraints
      volumeName: datanode-config
      namespace: {{ .Release.Namespace }}
      defaultMode: 0755
      keys:
        - hdfs-site.xml
  scripts:
    - name: hadoop-scripts
      templateRef: hadoop-scripts
      volumeName: scripts
      namespace: {{ .Release.Namespace }}
      defaultMode: 0755
```

> **设计原因**:
> 1. DataNode 保持 `hostNetwork: true` + `hostPID: true` + `dnsPolicy: ClusterFirstWithHostNet`（与 0.9 完全一致）
> 2. 单一 configs 条目（`datanode-config`），共享 `hadoop-core-config` 通过 cluster.yaml volumes 挂载
> 3. `configs[].keys: [hdfs-site.xml]`——与 0.9 datanode 的显式 keys 模式一致（0.9 中 datanode 是唯一有显式 keys 的数据组件）
> 4. DataNode 不需要 serviceRefDeclarations（不直接访问 ZK），不需要 vars（不需要跨组件动态变量）

### 6.9 ComponentVersion 文件（cmpv-*.yaml）

**文件**: `addons/hadoop/templates/cmpv-hadoop-core.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentVersion
metadata:
  name: hadoop-core
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.apiVersion" . | nindent 4 }}
spec:
  compatibilityRules:
    - releases:
        - v3.3.4
      compDefs:
        - hadoop-core
  releases:
    - name: v3.3.4
      serviceVersion: v3.3.4
      images:
        hadoop-core: {{ include "hadoop.coreImage" . | quote }}
```

**文件**: `addons/hadoop/templates/cmpv-hdfs-journalnode.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentVersion
metadata:
  name: hdfs-journalnode
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.apiVersion" . | nindent 4 }}
spec:
  compatibilityRules:
    - releases:
        - v3.3.4
      compDefs:
        - hdfs-journalnode
  releases:
    - name: v3.3.4
      serviceVersion: v3.3.4
      images:
        hadoop-common: {{ include "hadoop.commonImage" . | quote }}
        hdfs-journalnode: {{ include "hadoop.journalNodeImage" . | quote }}
```

**文件**: `addons/hadoop/templates/cmpv-hdfs-namenode.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentVersion
metadata:
  name: hdfs-namenode
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.apiVersion" . | nindent 4 }}
spec:
  compatibilityRules:
    - releases:
        - v3.3.4
      compDefs:
        - hdfs-namenode
  releases:
    - name: v3.3.4
      serviceVersion: v3.3.4
      images:
        hadoop-common: {{ include "hadoop.commonImage" . | quote }}
        hdfs-namenode: {{ include "hadoop.nameNodeImage" . | quote }}
```

**文件**: `addons/hadoop/templates/cmpv-hdfs-datanode.yaml`

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentVersion
metadata:
  name: hdfs-datanode
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.apiVersion" . | nindent 4 }}
spec:
  compatibilityRules:
    - releases:
        - v3.3.4
      compDefs:
        - hdfs-datanode
  releases:
    - name: v3.3.4
      serviceVersion: v3.3.4
      images:
        hadoop-common: {{ include "hadoop.commonImage" . | quote }}
        hdfs-datanode: {{ include "hadoop.dataNodeImage" . | quote }}
```

> **设计原因**:
> 1. 从单一的 `config-version.yaml` 拆分为 4 个独立 `cmpv-*.yaml`，与 redis 1.1 的 `cmpv-*.yaml` 模式一致
> 2. **`hadoop-common` 使用 `hadoop.commonImage` helper**: 0.9 硬编码 `apecloud/hadoop-common:v3.3.4`，1.1 通过 `image.common` 配置 + `hadoop.commonImage` helper 实现 SSOT
> 3. **`hadoop-common` 与组件专用镜像分离**: initContainer 使用通用 Hadoop 镜像，main container 使用组件专用镜像——与 0.9 行为完全一致
> 4. `hadoop-core` 的 images 仅需 `hadoop-core`（无 initContainer）
> **参考样例**: [redis cmpv-redis.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/cmpv-redis.yaml) 独立 ComponentVersion 文件
> **源验证**: [0.9 config-version.yaml](file:///Users/bytedance/project/tmp/kubeblocks-addons-release-0.9/addons/hadoop-hdfs/templates/config-version.yaml) L34-L36 `hadoop-common: "apecloud/hadoop-common:v3.3.4"`

### 6.10 ParametersDefinition 文件（paramsdef-*.yaml）

**文件**: `addons/hadoop/templates/paramsdef-hadoop-core.yaml`

```yaml
apiVersion: parameters.kubeblocks.io/v1alpha1
kind: ParametersDefinition
metadata:
  name: hadoop-core-config-constraints
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
spec:
  fileName: core-site.xml
  fileFormatConfig:
    format: xml
  parametersSchema:
    topLevelKey: HadoopCoreParameter
    cue: |-
      {{- .Files.Get "config/hadoop-core-config-constraint.cue" | nindent 6 }}
```

其他 3 个 paramsdef 文件同理，差异在 `name`、`fileName`、`topLevelKey`、CUE 文件引用。

> **设计原因**:
> 1. **apiVersion 为 `parameters.kubeblocks.io/v1alpha1`**（已验证 redis、kafka、mysql、zookeeper 1.1 全部使用此 API group）
> 2. `fileName` 对应配置模板中的文件名（`core-site.xml`、`hdfs-site.xml`）
> 3. CUE 文件从 `config/config-core-constraint.cue` 重命名为 `config/hadoop-core-config-constraint.cue`（与 ParametersDefinition name 对齐）
> **参考样例**: [redis paramsdef-redis.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/paramsdef-redis.yaml) L7（apiVersion: `parameters.kubeblocks.io/v1alpha1`）, [mysql paramsdef-80.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/mysql/templates/paramsdef-80.yaml) L2

### 6.11 ParamConfigRenderer 文件（pcr-*.yaml）

**文件**: `addons/hadoop/templates/pcr-hadoop-core.yaml`

```yaml
apiVersion: parameters.kubeblocks.io/v1alpha1
kind: ParamConfigRenderer
metadata:
  name: hadoop-core-config-renderer
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.annotations" . | nindent 4 }}
spec:
  componentDef: hadoop-core
  parametersDefs:
    - hadoop-core-config-constraints
  configs:
    - name: core-site.xml
      fileFormatConfig:
        format: xml
```

**文件**: `addons/hadoop/templates/pcr-hdfs-journalnode.yaml`

```yaml
apiVersion: parameters.kubeblocks.io/v1alpha1
kind: ParamConfigRenderer
metadata:
  name: hdfs-journalnode-config-renderer
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.annotations" . | nindent 4 }}
spec:
  componentDef: hdfs-journalnode
  parametersDefs:
    - journalnode-config-constraints
  configs:
    - name: hdfs-site.xml
      fileFormatConfig:
        format: xml
```

**文件**: `addons/hadoop/templates/pcr-hdfs-namenode.yaml`

```yaml
apiVersion: parameters.kubeblocks.io/v1alpha1
kind: ParamConfigRenderer
metadata:
  name: hdfs-namenode-config-renderer
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.annotations" . | nindent 4 }}
spec:
  componentDef: hdfs-namenode
  parametersDefs:
    - namenode-config-constraints
  configs:
    - name: hdfs-site.xml
      fileFormatConfig:
        format: xml
```

**文件**: `addons/hadoop/templates/pcr-hdfs-datanode.yaml`

```yaml
apiVersion: parameters.kubeblocks.io/v1alpha1
kind: ParamConfigRenderer
metadata:
  name: hdfs-datanode-config-renderer
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
  annotations:
    {{- include "hadoop.annotations" . | nindent 4 }}
spec:
  componentDef: hdfs-datanode
  parametersDefs:
    - datanode-config-constraints
  configs:
    - name: hdfs-site.xml
      fileFormatConfig:
        format: xml
```

> **设计原因**:
> 1. **apiVersion**: `parameters.kubeblocks.io/v1alpha1`（已验证 redis/kafka/mysql/zookeeper 1.1 PCR 全部使用此 API group）
> 2. **`componentDef` 使用文字名称**（非正则）：经验证 [kafka](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/_helpers.tpl) L71-L73 `componentDefName`（文字 `kafka-combine-{version}`）与 L78-L80 `cmpdRegexpPattern`（正则 `^kafka-combine-`）分离，PCR 的 `componentDef` 字段需要精确匹配 ComponentDefinition 名称，不支持正则。HDFS 为单版本，直接使用文字名 `hadoop-core` / `hdfs-journalnode` / `hdfs-namenode` / `hdfs-datanode`。
> 3. **`annotations`**: 包含 `hadoop.annotations`（`resourcePolicy` + `apiVersion`），与 [kafka pcr](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/pcr.yaml) L7-L9 一致。
> 4. **`configs[]` 中无 `templateRef`**：已验证 [redis pcr](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/pcr-redis.yaml) L18-L19、[kafka pcr](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/pcr.yaml) L14-L15、[mysql pcr](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/mysql/templates/pcr-80.yaml) L14-L22，`configs[]` 中均无 `templateRef` 字段。`templateRef` 仅在 ComponentDefinition 的 `configs[].templateRef` 中声明。
> 5. **单条目 PCR**——hadoop-core 管理 `core-site.xml`，数据组件各自管理 `hdfs-site.xml`。共享的 `core-site.xml` 由 hadoop-core 的 PCR 控制参数重渲染，通过 cluster.yaml `volumes[].configMap` 同步到所有数据组件。这是 HDFS 独有的"共享 ConfigMap"模式：与 redis/kafka/mysql（每个组件独立管理全部配置文件）不同，HDFS 的 `core-site.xml` 是**跨组件共享资源**，只需要一个 PCR 入口。
> 6. **无需 `reRenderResourceTypes`**：HDFS XML 配置不随 vscale/tls 变化，无需动态重渲染。
> **参考样例**:
> - PCR 结构: [redis pcr-redis.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/pcr-redis.yaml)
> - `componentDef` 文字名 vs 正则分离: [kafka _helpers.tpl](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/_helpers.tpl) L71-L80
> - annotations 模式: [mysql pcr-80.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/mysql/templates/pcr-80.yaml) L7-L9

### 6.12 配置模板文件（*-config-template.yaml）

每个组件的配置模板 ConfigMap 独立成一个文件：

```yaml
# hadoop-core-config-template.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: hadoop-core-config-template
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
data:
  core-site.xml: |-
    {{- .Files.Get "config/core-site.tpl" | nindent 4 }}
  log4j.properties: |-
    {{- .Files.Get "config/log4j.properties" | nindent 4 }}
```

```yaml
# hdfs-journalnode-config-template.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: journalnode-config-template
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
data:
  hdfs-site.xml: |-
    {{- .Files.Get "config/hdfs-journalnode.tpl" | nindent 4 }}
  log4j.properties: |-
    {{- .Files.Get "config/log4j.properties" | nindent 4 }}
```

namenode、datanode 的 config-template 同理，差异在 `metadata.name` 和 `.Files.Get` 引用的 `.tpl` 文件。

> **设计原因**: 每个组件独立一个 ConfigMap，精准控制每个组件可获取的配置文件集合。例如 journalnode 的 ConfigMap 不包含 hdfs-namenode.tpl。
> **参考样例**: [redis redis-config-template.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/redis-config-template.yaml)

### 6.13 hdfs-scripts-template.yaml（新增）

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: hadoop-scripts
  labels:
    {{- include "hadoop.labels" . | nindent 4 }}
data:
  check-journal-status.sh: |-
    {{- .Files.Get "scripts/check-journal-status.sh" | nindent 4 }}
  check-name-status.sh: |-
    {{- .Files.Get "scripts/check-name-status.sh" | nindent 4 }}
  check-data-status.sh: |-
    {{- .Files.Get "scripts/check-data-status.sh" | nindent 4 }}
```

> **设计原因**: 统一脚本 ConfigMap，所有组件的 `scripts.templateRef` 指向同一个 `hadoop-scripts`。对齐 redis 1.1 的 `redis-scripts-template.yaml` 模式。
> **参考样例**: [redis-scripts-template.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/)

### 6.14 config/* 文件变更

| 0.9 文件 | 1.1 文件 | 操作 | 说明 |
|---------|---------|------|------|
| `config-core-constraint.cue` | `hadoop-core-config-constraint.cue` | 重命名 | 对齐 ParametersDefinition name |
| `config-datanode-constraint.cue` | `hdfs-datanode-config-constraint.cue` | 重命名 | 同上 |
| `config-journalnode-constraint.cue` | `hdfs-journalnode-config-constraint.cue` | 重命名 | 同上 |
| `config-namenode-constraint.cue` | `hdfs-namenode-config-constraint.cue` | 重命名 | 同上 |
| `core-site.tpl` | `core-site.tpl` | 不变 | - |
| `hdfs-datanode.tpl` | `hdfs-datanode.tpl` | 不变 | - |
| `hdfs-journalnode.tpl` | `hdfs-journalnode.tpl` | 不变 | - |
| `hdfs-namenode.tpl` | `hdfs-namenode.tpl` | 不变 | - |
| `log4j.properties` | `log4j.properties` | 不变 | - |

所有 `.tpl`、`.properties`、`.sh` 文件内容零修改。

### 6.15 README.md 和 releases_notes.yaml

> **设计原因**: 0.9 无 README，1.1 新增以对齐其他 addon。结构和内容参考 redis 1.1 README，适配 HDFS 场景。
> **参考样例**: [redis README.md](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/README.md)

---

## 7. addons-cluster 部署层迁移方案

### 7.1 Chart.yaml

```yaml
annotations:
  category: BigData
apiVersion: v2
name: hadoop
type: application
version: 1.1.0-alpha.0
description: A Hadoop HDFS cluster Helm chart for KubeBlocks.
dependencies:
  - name: kblib
    version: 0.1.2
    repository: file://../kblib
    alias: extra
appVersion: "3.3.4"
keywords:
  - hadoop
  - hdfs
  - bigdata
home: https://github.com/apecloud/kubeblocks/tree/main/deploy/hadoop
icon: https://kubeblocks.io/img/logo.png
maintainers:
  - name: ApeCloud
    url: https://kubeblocks.io/
sources:
  - https://github.com/apecloud/kubeblocks/
```

> **设计原因**: kblib 依赖从 `kblib-v2 0.1.1`（0.9）→ `kblib 0.1.2`（1.1），version 从 0.1.0/0.1 升到 1.1.0-alpha.0。
> **参考样例**: [redis addons-cluster Chart.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons-cluster/redis/Chart.yaml)

### 7.2 values.yaml

```yaml
replicas:
  core: 1
  journalnode: 3
  namenode: 2
  datanode: 1

resources:
  core:
    requests:
      cpu: "0.5"
      memory: 0.5Gi
    limits:
      cpu: "0.5"
      memory: 2Gi
  journalnode:
    requests:
      cpu: "0.5"
      memory: 0.5Gi
    limits:
      cpu: "0.5"
      memory: 2Gi
  namenode:
    requests:
      cpu: "0.5"
      memory: 0.5Gi
    limits:
      cpu: "0.5"
      memory: 2Gi
  datanode:
    requests:
      cpu: "0.5"
      memory: 0.5Gi
    limits:
      cpu: "0.5"
      memory: 2Gi

storage:
  journalnode: 10Gi
  namenode: 10Gi
  datanode: 30Gi

serviceRefs:
  hadoopZookeeper:
    namespace: default
    clusterServiceSelector:
      cluster: zkcluster
      service:
        component: zookeeper
        service: headless
        port: client

extra:
  terminationPolicy: Delete
```

> **设计原因**:
> 1. 移除顶层 `clusterDefinitionRef: hadoop-hdfs`（cluster.yaml 中已硬编码为 `clusterDef: hadoop`）
> 2. 移除顶层 `topology: hadoop-ha-cluster`（同上理）
> 3. 移除 `serviceAccount` 配置（kblib 自动管理）
> 4. 移除 `terminationPolicy` 顶层字段（下沉到 `extra.terminationPolicy`，由 kblib clusterCommon 模板读取）
> **参考样例**: [redis addons-cluster values.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons-cluster/redis/values.yaml) `extra.terminationPolicy`

### 7.3 _helpers.tpl

```gotmpl
{{- define "hadoop-cluster.clusterCommon" }}
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

> **设计原因**: 精简 helpers，仅保留 `clusterCommon`（被 cluster.yaml 引用生成 Cluster CR 头部）。移除 0.9 的 `name/fullname/chart/labels/serviceAccountName/clustername` 函数（kblib 已提供等价功能）。移除 Legacy ComponentSpec helpers（0.9 中不存在）。

### 7.4 cluster.yaml

```yaml
{{- include "hadoop-cluster.clusterCommon" . }}
  clusterDef: hadoop
  topology: ha-cluster
  componentSpecs:
    - name: hadoop-core
      componentDef: hadoop-core
      serviceRefs:
        - name: hadoopZookeeper
          namespace: {{ .Values.serviceRefs.hadoopZookeeper.namespace }}
          clusterServiceSelector:
            cluster: {{ .Values.serviceRefs.hadoopZookeeper.clusterServiceSelector.cluster }}
            service:
              component: {{ .Values.serviceRefs.hadoopZookeeper.clusterServiceSelector.service.component }}
              service: {{ .Values.serviceRefs.hadoopZookeeper.clusterServiceSelector.service.service }}
              port: {{ .Values.serviceRefs.hadoopZookeeper.clusterServiceSelector.service.port }}
      replicas: {{ .Values.replicas.core }}
      resources:
        requests:
          cpu: {{ .Values.resources.core.requests.cpu | quote }}
          memory: {{ .Values.resources.core.requests.memory }}
        limits:
          cpu: {{ .Values.resources.core.limits.cpu | quote }}
          memory: {{ .Values.resources.core.limits.memory }}
    - name: journalnode
      componentDef: hdfs-journalnode
      replicas: {{ .Values.replicas.journalnode }}
      resources:
        requests:
          cpu: {{ .Values.resources.journalnode.requests.cpu | quote }}
          memory: {{ .Values.resources.journalnode.requests.memory }}
        limits:
          cpu: {{ .Values.resources.journalnode.limits.cpu | quote }}
          memory: {{ .Values.resources.journalnode.limits.memory }}
      volumes:
        - name: hadoop-core-config
          configMap:
            name: {{ include "kblib.clusterName" . }}-hadoop-core-config
      volumeClaimTemplates:
        - name: edits-dir
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: {{ .Values.storage.journalnode }}
    - name: namenode
      componentDef: hdfs-namenode
      serviceRefs:
        - name: hadoopZookeeper
          namespace: {{ .Values.serviceRefs.hadoopZookeeper.namespace }}
          clusterServiceSelector:
            cluster: {{ .Values.serviceRefs.hadoopZookeeper.clusterServiceSelector.cluster }}
            service:
              component: {{ .Values.serviceRefs.hadoopZookeeper.clusterServiceSelector.service.component }}
              service: {{ .Values.serviceRefs.hadoopZookeeper.clusterServiceSelector.service.service }}
              port: {{ .Values.serviceRefs.hadoopZookeeper.clusterServiceSelector.service.port }}
      replicas: {{ .Values.replicas.namenode }}
      resources:
        requests:
          cpu: {{ .Values.resources.namenode.requests.cpu | quote }}
          memory: {{ .Values.resources.namenode.requests.memory }}
        limits:
          cpu: {{ .Values.resources.namenode.limits.cpu | quote }}
          memory: {{ .Values.resources.namenode.limits.memory }}
      volumes:
        - name: hadoop-core-config
          configMap:
            name: {{ include "kblib.clusterName" . }}-hadoop-core-config
      volumeClaimTemplates:
        - name: metadata-dir
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: {{ .Values.storage.namenode }}
    - name: datanode
      componentDef: hdfs-datanode
      replicas: {{ .Values.replicas.datanode }}
      resources:
        requests:
          cpu: {{ .Values.resources.datanode.requests.cpu | quote }}
          memory: {{ .Values.resources.datanode.requests.memory }}
        limits:
          cpu: {{ .Values.resources.datanode.limits.cpu | quote }}
          memory: {{ .Values.resources.datanode.limits.memory }}
      volumes:
        - name: hadoop-core-config
          configMap:
            name: {{ include "kblib.clusterName" . }}-hadoop-core-config
      volumeClaimTemplates:
        - name: hdfs-data-0
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: {{ .Values.storage.datanode }}
```

> **设计原因**:
> 1. **`clusterDef: hadoop`**: `clusterDefinitionRef: hadoop-hdfs` (0.9) → `clusterDef: hadoop` (1.1)——与 addons/ 目录名一致
> 2. **`topology: ha-cluster`**: `hadoop-ha-cluster` → `ha-cluster`（简化，ClusterDefinition 上下文中 hadoop 前缀冗余）
> 3. **`componentSpecs[].name` 必须匹配 `topology.components[].name`**：使用短名 `journalnode`、`namenode`、`datanode`（经验证，1.1 ClusterDefinition 保持 `components: [{name, compDef}]` 结构）
> 4. **移除 `{{ include "kblib.affinity" . }}`**：0.9 cluster.yaml 中的 affinity 调用在 1.1 kblib 中不存在对应模板（已验证 kblib clusterCommon 不含 affinity）
> 5. **`componentDef` 引用 ComponentDefinition 全名**: `hdfs-journalnode`、`hdfs-namenode`、`hdfs-datanode`
> 
> **关键验证**: `topology.components[].name` 与 `componentSpecs[].name` 的对应关系：
> - topology: `name: journalnode` → cluster.yaml: `name: journalnode` ✅
> - topology: `name: namenode` → cluster.yaml: `name: namenode` ✅  
> - topology: `name: datanode` → cluster.yaml: `name: datanode` ✅
>
> **参考样例**: [kafka addons-cluster cluster.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons-cluster/kafka/templates/cluster.yaml) L8-L10（`clusterDef` + `topology` + `componentSpecs` 用法）

### 7.5 values.schema.json

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "replicas": {
      "type": "object",
      "properties": {
        "core": { "type": "integer", "default": 1, "minimum": 1 },
        "journalnode": { "type": "integer", "default": 3, "minimum": 3 },
        "namenode": { "type": "integer", "default": 2, "minimum": 2, "maximum": 2 },
        "datanode": { "type": "integer", "default": 1, "minimum": 1 }
      }
    },
    "resources": {
      "type": "object",
      "properties": {
        "core": { "$ref": "#/definitions/resourceSchema" },
        "journalnode": { "$ref": "#/definitions/resourceSchema" },
        "namenode": { "$ref": "#/definitions/resourceSchema" },
        "datanode": { "$ref": "#/definitions/resourceSchema" }
      }
    },
    "storage": {
      "type": "object",
      "properties": {
        "journalnode": { "type": "string", "default": "10Gi" },
        "namenode": { "type": "string", "default": "10Gi" },
        "datanode": { "type": "string", "default": "30Gi" }
      }
    },
    "serviceRefs": {
      "type": "object",
      "properties": {
        "hadoopZookeeper": {
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
        }
      }
    }
  },
  "definitions": {
    "resourceSchema": {
      "type": "object",
      "properties": {
        "requests": {
          "type": "object",
          "properties": {
            "cpu": { "type": "string", "default": "0.5" },
            "memory": { "type": "string", "default": "0.5Gi" }
          }
        },
        "limits": {
          "type": "object",
          "properties": {
            "cpu": { "type": "string", "default": "0.5" },
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

## 8. 第1轮自检：Topology 结构验证（🚨 发现致命问题）

### 8.1 问题描述

原始设计方案中 ClusterDefinition 使用了 `compDefs: [...]` 扁平列表。经过对 kafka、mysql、redis 1.1 的 ClusterDefinition 文件逐行验证：

**验证结果**: 1.1 v1 ClusterDefinition 的 `topology` 结构保持 `components: [{name, compDef}]`——**不是** `compDefs: [...]` 扁平列表。

### 8.2 修复方案

```diff
spec:
  topologies:
    - name: ha-cluster
-     compDefs:
-       - hadoop-core
-       - hdfs-journalnode
+     components:
+       - name: hadoop-core
+         compDef: {{ include "hadoop.hadoopCoreCmpdRegexPattern" . }}
+       - name: journalnode
+         compDef: {{ include "hadoop.hdfsJournalnodeCmpdRegexPattern" . }}
```

### 8.3 影响范围

1. cluster.yaml `componentSpecs[].name` 必须匹配 `topology.components[].name`（`journalnode`，不是 `hdfs-journalnode`）
2. orders 必须引用 `topology.components[].name`（`journalnode`，不是 `hdfs-journalnode`）

### 8.4 修复状态

✅ ClusterDefinition 结构已修复
✅ cluster.yaml componentNombre 已对齐
✅ orders 引用已对齐

> **参考**: [kafka clusterdefinition.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/clusterdefinition.yaml) L13-L16 `components: [{name, compDef}]`

---

## 9. 第2轮自检：API 版本验证（🚨 发现致命问题）

### 9.1 ParametersDefinition/ParamConfigRenderer apiVersion

**原始设计**: `apiVersion: apps.kubeblocks.io/v1alpha1`

**验证过程**: 逐文件检查 redis、kafka、mysql、zookeeper 1.1 addons 的 paramsdef 和 pcr 文件：
- [redis paramsdef-redis.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/paramsdef-redis.yaml) L7: `parameters.kubeblocks.io/v1alpha1`
- [kafka paramsdef.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/paramsdef.yaml): `parameters.kubeblocks.io/v1alpha1`
- [mysql paramsdef-80.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/mysql/templates/paramsdef-80.yaml) L2: `parameters.kubeblocks.io/v1alpha1`
- [zookeeper paramsdef.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/zookeeper/templates/paramsdef.yaml): `parameters.kubeblocks.io/v1alpha1`

**结论**: **全部使用** `parameters.kubeblocks.io/v1alpha1`，**无一使用** `apps.kubeblocks.io/v1alpha1`。

### 9.2 其他 API 版本验证

| CRD | apiVersion | 状态 |
|-----|-----------|------|
| ClusterDefinition | `apps.kubeblocks.io/v1` | ✅ |
| ComponentDefinition | `apps.kubeblocks.io/v1` | ✅ |
| ComponentVersion | `apps.kubeblocks.io/v1` | ✅ |
| Cluster | `apps.kubeblocks.io/v1` | ✅ |
| ParametersDefinition | `parameters.kubeblocks.io/v1alpha1` | ✅ |
| ParamConfigRenderer | `parameters.kubeblocks.io/v1alpha1` | ✅ |

---

## 10. 第3轮自检：集群拓扑 → 部署层集成验证

### 10.1 componentSpec name 对齐

| topology.components.name | componentSpecs.name | componentSpecs.componentDef | 状态 |
|-------------------------|--------------------|---------------|------|
| `hadoop-core` | `hadoop-core` | `hadoop-core` | ✅ |
| `journalnode` | `journalnode` | `hdfs-journalnode` | ✅ |
| `namenode` | `namenode` | `hdfs-namenode` | ✅ |
| `datanode` | `datanode` | `hdfs-datanode` | ✅ |

### 10.2 orders 验证

```yaml
orders:
  provision:
    - hadoop-core
    - journalnode      # ← 引用 topology.components.name（短名）
    - namenode
    - datanode
  terminate:
    - datanode
    - namenode
    - journalnode
    - hadoop-core
```

**验证**: orders 中的名称必须与 `topology.components[].name` 匹配——已验证与 kafka orders 模式一致。

### 10.3 `clusterDef` vs `clusterDefinitionRef` 验证

0.9: `clusterDefinitionRef: hadoop-hdfs`
1.1: `clusterDef: hadoop`

已验证 kafka 1.1 cluster.yaml L8 使用 `clusterDef: kafka`。

---

## 11. 第4轮自检：ComponentVersion 镜像引用一致性

### 11.1 hadoop-common 镜像问题

**0.9 行为**: 所有 3 个数据组件的 ComponentVersion 中 `hadoop-common` 硬编码为 `apecloud/hadoop-common:v3.3.4`（与组件专用镜像 **不同**）。

**原始设计**: 每个组件的 ComponentVersion 中 `hadoop-common` 使用组件自身镜像（如 `hadoop.journalNodeImage`）。

**问题**: 这违反了 SSOT 原则——init container（`hadoop-common`）应该始终使用通用 Hadoop 镜像，因为 init 命令（`cp -r /opt/software/hadoop-3.3.4/*`）依赖通用 Hadoop 二进制路径。

### 11.2 修复方案

新增 `image.common` 配置 + `hadoop.commonImage` helper：

```yaml
# values.yaml
image:
  common:
    registry: docker.io
    repository: apecloud/hadoop-common
    tag: "v3.3.4"

# ComponentVersion
images:
  hadoop-common: {{ include "hadoop.commonImage" . | quote }}  # ← 统一通用镜像
  hdfs-journalnode: {{ include "hadoop.journalNodeImage" . | quote }}  # ← 组件专用镜像
```

**状态**: ✅ 已修复

---

## 12. 第5轮自检：跨组件变量引用验证

### 12.1 `componentVarRef` 差异

| 组件 | 变量 | componentVarRef | compDef | 说明 |
|------|------|----------------|---------|------|
| hdfs-journalnode | `JOURNALNODE_POD_FQDN_LIST` | `podFQDNs: Required` | 不指定（自身引用） | JournalNode 获取自己的 Pod FQDN |
| hdfs-namenode | `JOURNALNODE_POD_FQDN_LIST` | `podFQDNs: Required` | `compDef: hdfs-journalnode` | NameNode 获取 JournalNode 的 FQDN |

**验证**: journalnode 不指定 `compDef` = 自身引用，namenode 指定 `compDef: hdfs-journalnode` = 跨组件引用。两者行为不同且正确。

### 12.2 `serviceRefVarRef` 验证

| 组件 | 变量 | serviceRef | 
|------|------|-----------|
| hadoop-core | `ZOOKEEPER_ENDPOINTS` | `hadoopZookeeper` | ✅ (cluster.yaml 有 serviceRefs) |
| hdfs-namenode | `ZOOKEEPER_ENDPOINTS` | `hadoopZookeeper` | ✅ (cluster.yaml 有 serviceRefs) |

ZK serviceRef 声明在 hadoop-core 和 hdfs-namenode 的 ComponentDefinition 中（两者都通过 `serviceRefDeclarations` 声明 `hadoopZookeeper` 依赖），cluster.yaml 为两个组件均绑定 serviceRefs。hdfs-namenode.tpl 使用 ZOOKEEPER_ENDPOINTS 渲染 ha.zookeeper.quorum，因此必须显式绑定。

---

## 13. 第6轮自检：配置系统完整性验证（🚨 发现 PCR 问题）

### 13.1 PCR 设计问题（重新审查发现）

重新对比 redis/kafka/mysql 1.1 PCR 文件后发现 4 个问题：

**问题 1: `configs[]` 中存在冗余 `templateRef` 字段**

已验证 [redis pcr](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/pcr-redis.yaml) L18-L19、[kafka pcr](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/pcr.yaml) L14-L15、[mysql pcr](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/mysql/templates/pcr-80.yaml) L14-L22，`configs[]` 中均无 `templateRef` 字段。`templateRef` 绑定仅在 ComponentDefinition 的 `configs[].templateRef` 中声明。

**状态**: ✅ 已移除所有 PCR 中的 `templateRef`

**问题 2: PCR 缺少 `annotations` 字段**

已验证 redis/kafka/mysql 1.1 PCR 全部包含 `annotations`（含 `resourcePolicy` + `apiVersion`）：

| addon | 文件 | 引用 |
|-------|------|-----|
| redis | [pcr-redis.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/redis/templates/pcr-redis.yaml) L8-L10 | `{{ include "redis.annotations" $ ... }}` |
| kafka | [pcr.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/pcr.yaml) L7-L9 | `{{ include "kafka.annotations" . ... }}` |
| mysql | [pcr-80.yaml](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/mysql/templates/pcr-80.yaml) L7-L9 | `{{ include "mysql.annotations" . ... }}` |

**修复**: 新增 `hadoop.annotations` helper（含 `resourcePolicy` + `apiVersion`），为所有 4 个 PCR 添加 annotations。

**状态**: ✅ 已修复

**问题 3: PCR `componentDef` 使用正则而非文字名称**

已验证 [kafka _helpers.tpl](file:///Users/bytedance/project/kubeblocks-addons-release-1.1/addons/kafka/templates/_helpers.tpl)：
- L71-L73 `kafka-combine.componentDefName` = `kafka-combine-{{ .Chart.Version }}`（**文字名称**，用于 PCR）
- L78-L80 `kafka-combine.cmpdRegexpPattern` = `^kafka-combine-`（**正则**，用于 ClusterDefinition 和 ComponentVersion）

PCR 的 `componentDef` 字段需要精确匹配 ComponentDefinition 名称，不支持正则匹配。原始设计中使用 `{{ include "hadoop.hadoopCoreCmpdRegexPattern" . }}`（正则 `^hadoop-core$`）虽然在功能上等价于 `hadoop-core`，但不符合 1.1 惯例。

**修复**: 所有 4 个 PCR 的 `componentDef` 改用文字名称：`hadoop-core`、`hdfs-journalnode`、`hdfs-namenode`、`hdfs-datanode`。

**状态**: ✅ 已修复

**问题 4（重新审查发现）: 数据组件 cmpd 错误包含共享 ConfigMap**

通过逐文件对比 0.9 源文件发现：在 0.9 中，`hadoop-core-config`（core-site.xml）是**单点生成、跨组件共享**的模式：

| 组件 | 0.9 `configs[]` | `hadoop-core-config` 来源 |
|------|----------------|--------------------------|
| hadoop-core | `templateRef: hadoop-core-config-template` | **自己生成**（有 ZK serviceRefs） |
| journalnode | `templateRef: journalnode-config-template` | cluster.yaml `volumes[].configMap` 共享 |
| namenode | `templateRef: namenode-config-template` | cluster.yaml `volumes[].configMap` 共享 |
| datanode | `templateRef: datanode-config-template` | cluster.yaml `volumes[].configMap` 共享 |

**0.9 源文件验证**:
- [cmpd-journalnode.yaml](file:///Users/bytedance/project/tmp/kubeblocks-addons-release-0.9/addons/hadoop-hdfs/templates/cmpd-journalnode.yaml) L113-119: 仅有 `templateRef: journalnode-config-template`
- [cmpd-namenode.yaml](file:///Users/bytedance/project/tmp/kubeblocks-addons-release-0.9/addons/hadoop-hdfs/templates/cmpd-namenode.yaml) L125-131: 仅有 `templateRef: namenode-config-template`
- [cmpd-datanode.yaml](file:///Users/bytedance/project/tmp/kubeblocks-addons-release-0.9/addons/hadoop-hdfs/templates/cmpd-datanode.yaml) L95-103: 仅有 `templateRef: datanode-config-template`

而 1.1 原始设计中每个数据组件的 `configs[]` 都增加了 `hadoop-core-config` 条目，导致：
1. 数据组件会**独立渲染** core-site.xml，但其 `ZOOKEEPER_ENDPOINTS` 无法解析（只有 hadoop-core 有 serviceRefs）
2. 与 cluster.yaml 中的显式 `volumes[].configMap: {clusterName}-hadoop-core-config` 产生重复生成冲突

**修复**: 
1. 从 jn/nn/dn cmpd `configs[]` 中移除 `hadoop-core-config` 条目（恢复 0.9 模式）
2. 数据组件 PCR 从双条目简化为单条目（仅管理 `hdfs-site.xml`）
3. `core-site.xml` 参数重渲染由 hadoop-core 的 PCR 统一控制，通过 cluster.yaml volumes 同步

**状态**: ✅ 已修复

### 13.2 ConfigMap → ComponentDefinition 挂载矩阵

| ComponentDefinition | cmpd configs[].templateRef | volumeMounts (挂载键) | 文件路径 |
|---------------------|---------------------------|----------------------|---------|
| hadoop-core | `hadoop-core-config-template` | core-site.xml, log4j.properties | /hadoop/conf/ |
| hdfs-journalnode | `journalnode-config-template` | hdfs-site.xml | /hadoop/conf/ |
| hdfs-journalnode | *(cluster.yaml volumes)* | core-site.xml, log4j.properties | /hadoop/conf/ |
| hdfs-namenode | `namenode-config-template` | hdfs-site.xml | /hadoop/conf/ |
| hdfs-namenode | *(cluster.yaml volumes)* | core-site.xml, log4j.properties | /hadoop/conf/ |
| hdfs-datanode | `datanode-config-template` | hdfs-site.xml | /hadoop/conf/ |
| hdfs-datanode | *(cluster.yaml volumes)* | core-site.xml, log4j.properties | /hadoop/conf/ |

> **关键设计**: `hadoop-core-config-template` 仅由 hadoop-core 的 `configs[]` 引用（单点生成）。数据组件通过 cluster.yaml 的 `volumes[].configMap` 共享挂载生成的 ConfigMap，不独立渲染。这保证了 `ZOOKEEPER_ENDPOINTS` 等变量只通过 hadoop-core 的上下文（有 serviceRefs）解析一次。

### 13.3 变量 → 配置模板注入验证

| 模板 | 变量 | 来源 | 在 1.1 中可用？ |
|------|------|------|----------------|
| `core-site.tpl` | `KB_CLUSTER_NAME` | 内置 | ✅ |
| `core-site.tpl` | `ZOOKEEPER_ENDPOINTS` | serviceRefVarRef | ✅ |
| `hdfs-namenode.tpl` | `KB_NAMESPACE` | 内置 | ✅ |
| `hdfs-namenode.tpl` | `JOURNALNODE_POD_FQDN_LIST` | componentVarRef | ✅ |

### 13.4 `configs[].keys` 补齐

0.9 中 3 个数据组件缺少或仅有部分 keys。1.1 全部显式声明：

```
✔ hadoop-core:     [core-site.xml] (log4j 新增挂载)
✔ hdfs-journalnode: [hdfs-site.xml] (0.9 无 keys，1.1 显式声明)
✔ hdfs-namenode:   [hdfs-site.xml] (0.9 无 keys，1.1 显式声明)
✔ hdfs-datanode:   [hdfs-site.xml] (0.9 已有 keys，保持不变)
```

> **说明**: `log4j.properties` 是静态文件（无 Go Template 变量），不需要在 keys 中声明。hadoop-core 的 `core-site.xml` 需要 Go Template 渲染（`ZOOKEEPER_ENDPOINTS`、`KB_CLUSTER_NAME`），数据组件的 `hdfs-site.xml` 需要 Go Template 渲染（`JOURNALNODE_POD_FQDN_LIST`）。

---

## 14. 第7轮自检：网络与健康检查验证

### 14.1 hostNetwork 配置

DataNode hostNetwork 配置逐字段对比：
- `hostNetwork: true` ✅
- `hostPID: true` ✅
- `dnsPolicy: ClusterFirstWithHostNet` ✅

与 0.9 完全一致。

### 14.2 健康检查

| 组件 | Liveness | Readiness | Probe 脚本 | 状态 |
|------|----------|----------|------------|------|
| hadoop-core | ❌ | ❌ | 无 | ✅ 编排组件 |
| hdfs-journalnode | ✅ | ✅ | check-journal-status.sh | ✅ |
| hdfs-namenode | ✅ | ✅ | check-name-status.sh | ✅ |
| hdfs-datanode | ✅ | ✅ | check-data-status.sh | ✅ |

Probe 脚本路径 `/kubeblocks/scripts/` 不变。

### 14.3 DataNode 端口

0.9 中 DataNode 容器 spec 无显式 `ports` 声明（hostNetwork 模式下 DataNode 使用默认端口 9864-9867）。1.1 保持不变。

---

## 15. 第8轮自检：最终一致性交叉验证

### 15.1 全量交叉引用矩阵

| 0.9 → | 1.1 → | 引用一致性 |
|--------|-------|----------|
| ClusterDefinition name: `hadoop-hdfs` | ClusterDefinition name: `hadoop` | ✅ Cluster.yaml `clusterDef: hadoop` 匹配 |
| Topology name: `hadoop-ha-cluster` | Topology name: `ha-cluster` | ✅ Cluster.yaml `topology: ha-cluster` 匹配 |
| Topology `components[{name: journalnode, compDef: hdfs-journalnode}]` | 结构不变 | ✅ 已验证 kafka 1.1 使用相同结构 |
| ConfigConstraint (v1beta1) | ParametersDefinition (v1alpha1) | ✅ 已验证 apiVersion `parameters.kubeblocks.io/v1alpha1` |
| `clusterDefinitionRef` | `clusterDef` | ✅ Cluster.yaml 使用新字段 |
| `scripts[].templateRef: hadoop-hdfs-scripts` | `scripts[].templateRef: hadoop-scripts` | ✅ |
| CM `hadoop-core-config-template` | 不变 | ✅ |
| ComponentVersion `hadoop-common` 硬编码 | `hadoop.commonImage` helper | ✅ SSOT |
| PCR `configs[].templateRef` | **移除** | ✅ 验证 redis/kafka/mysql PCR 均无此字段 |
| PCR `componentDef` 正则 | **文字名称** | ✅ `hadoop-core` / `hdfs-journalnode` / etc. |
| PCR `annotations` | **新增** | ✅ `hadoop.annotations` (resourcePolicy + apiVersion) |
| cmpd data 组件 `hadoop-core-config` in configs[] | **移除** | ✅ 恢复 0.9 共享 ConfigMap 模式（仅 hadoop-core 生成，cluster.yaml volumes 共享） |
| PCR 单条目 for jn/nn/dn | **简化** | ✅ data 组件 PCR 仅管理 `hdfs-site.xml`，core-site.xml 由 hadoop-core PCR 统一管理 |

### 15.2 最终检查清单

| # | 检查项 | 0.9 值 | 1.1 值 | 结果 |
|---|--------|--------|--------|------|
| 1 | ClusterDefinition apiVersion | v1alpha1 | v1 | ✅ |
| 2 | ComponentDefinition apiVersion | v1alpha1 | v1 | ✅ |
| 3 | ComponentVersion apiVersion | v1alpha1 | v1 | ✅ |
| 4 | Cluster apiVersion | v1alpha1 | v1 | ✅ |
| 5 | ParametersDefinition apiVersion | 无 (ConfigConstraint v1beta1) | **parameters.kubeblocks.io/v1alpha1** | ✅ |
| 6 | ParamConfigRenderer apiVersion | 无 | **parameters.kubeblocks.io/v1alpha1** | ✅ |
| 7 | Topology 结构 | `components[{name, compDef}]` | **不变** | ✅ |
| 8 | `clusterDefinitionRef` → `clusterDef` | hadoop-hdfs | hadoop | ✅ |
| 9 | addons 目录 | `hadoop-hdfs/` | `hadoop/` | ✅ |
| 10 | addons-cluster 目录 | `hadoop-cluster/` | `hadoop/` | ✅ |
| 11 | kblib addons | 无 | kblib 0.1.0 | ✅ |
| 12 | kblib addons-cluster | kblib-v2 0.1.1 | kblib 0.1.2 | ✅ |
| 13 | ConfigMap 拆分 | 1 文件 4 CM | 4 独立文件 | ✅ |
| 14 | ComponentVersion 拆分 | 1 文件 | 4 独立文件 | ✅ |
| 15 | initContainer 镜像 | 硬编码 hadoop-common | `hadoop.commonImage` helper (SSOT) | ✅ |
| 16 | `configs[].keys` 显式声明 | 缺失 | 全部补齐 | ✅ |
| 17 | cmpd-hadoop-core image 字段 | 缺失 | 已添加 | ✅ |
| 18 | cmpd-hadoop-core log4j 挂载 | 缺失 | 已添加 | ✅ |
| 19 | constraintRef 恢复 | journalnode/namenode 被注释 | 已恢复 | ✅ |
| 20 | orders 与 topology component name 对齐 | - | ✅ (journalnode/namenode/datanode) | ✅ |
| 21 | cluster.yaml componentSpec name 与 topology 一致 | - | ✅ | ✅ |
| 22 | 零功能回归 | - | - | ✅ |
| 23 | PCR `configs[].templateRef` | 存在冗余字段 | **已移除** | ✅ |
| 24 | PCR `componentDef` | 正则 `^hadoop-core$` | **文字名称** `hadoop-core` | ✅ |
| 25 | PCR `annotations` | 缺失 | **已添加** `hadoop.annotations` | ✅ |
| 26 | 共享 ConfigMap 模式恢复 | data cmpd 错误包含 hadoop-core-config | **已移除**：仅 hadoop-core 生成，cluster.yaml volumes 共享 | ✅ |
| 27 | PCR 单条目（原双条目修正） | jn/nn/dn PCR 双参数定义+双配置 | **简化**：各组件 PCR 仅管理自身 hdfs-site.xml | ✅ |
| 28 | updateStrategy 层级 | spec.runtime.updateStrategy | **spec.updateStrategy** 顶层（对齐 kafka/redis 1.1） | ✅ |
| 29 | cluster.yaml namenode ZK serviceRefs | 缺失（ZOOKEEPER_ENDPOINTS 无法解析） | **已添加**（hdfs-namenode.tpl 引用 ZOOKEEPER_ENDPOINTS） | ✅ |

---

## 附录 A：文件映射速查表

| 0.9 路径 | → | 1.1 路径 |
|----------|---|---------|
| `addons/hadoop-hdfs/Chart.yaml` | → | `addons/hadoop/Chart.yaml` |
| `addons/hadoop-hdfs/values.yaml` | → | `addons/hadoop/values.yaml` |
| `addons/hadoop-hdfs/templates/_helpers.tpl` | → | `addons/hadoop/templates/_helpers.tpl` |
| `addons/hadoop-hdfs/templates/clusterdefinition.yaml` | → | `addons/hadoop/templates/clusterdefinition.yaml` |
| `addons/hadoop-hdfs/templates/cmpd-hadoop-core.yaml` | → | `addons/hadoop/templates/cmpd-hadoop-core.yaml` |
| `addons/hadoop-hdfs/templates/cmpd-journalnode.yaml` | → | `addons/hadoop/templates/cmpd-hdfs-journalnode.yaml` |
| `addons/hadoop-hdfs/templates/cmpd-namenode.yaml` | → | `addons/hadoop/templates/cmpd-hdfs-namenode.yaml` |
| `addons/hadoop-hdfs/templates/cmpd-datanode.yaml` | → | `addons/hadoop/templates/cmpd-hdfs-datanode.yaml` |
| `addons/hadoop-hdfs/templates/config-version.yaml` | → | `addons/hadoop/templates/cmpv-*.yaml` (4 文件) |
| `addons/hadoop-hdfs/templates/config-constraint.yaml` | → | `addons/hadoop/templates/paramsdef-*.yaml` (4 文件) |
| - | → | `addons/hadoop/templates/pcr-*.yaml` (4 文件) |
| `addons/hadoop-hdfs/templates/config-configmap.yaml` | → | `addons/hadoop/templates/*-config-template.yaml` (4 文件) |
| - | → | `addons/hadoop/templates/hdfs-scripts-template.yaml` |
| `addons/hadoop-hdfs/templates/scripts.yaml` | → | `addons/hadoop/templates/scripts.yaml` (空) |
| `addons-cluster/hadoop-cluster/Chart.yaml` | → | `addons-cluster/hadoop/Chart.yaml` |
| `addons-cluster/hadoop-cluster/values.yaml` | → | `addons-cluster/hadoop/values.yaml` |
| `addons-cluster/hadoop-cluster/templates/cluster.yaml` | → | `addons-cluster/hadoop/templates/cluster.yaml` |

---

## 附录 B：0.9 已知问题与 1.1 修复映射

| # | 0.9 问题 | 1.1 修复 | 状态 |
|---|---------|---------|------|
| 1 | cmpd-hadoop-core 缺少 `image:` 字段 | 添加 `image: {{ include "hadoop.coreImage" . }}` | ✅ |
| 2 | cmpd-hadoop-core 未挂载 `log4j.properties` | 新增 volumeMount + configs.keys | ✅ |
| 3 | journalnode/namenode 的 `constraintRef` 被注释 | 恢复 + 新增 ParametersDefinition | ✅ |
| 4 | configs[].keys 隐式依赖 volumeMount | 全部显式声明 keys | ✅ |
| 5 | datanode keys 仅 `[hdfs-site.xml]`（log4j 通过 ConfigMap 数据静态提供） | 保持不变（静态文件无需 Go Template 渲染） | ✅ |
| 6 | `hadoop-common` 镜像硬编码 | `image.common` + `hadoop.commonImage` helper | ✅ |
| 7 | values.yaml 大量未使用默认值 | 精简至仅必需配置 | ✅ |
| 8 | 缺少 README/releases_notes | 新增 | ✅ |
| 9 | hadoop-core ConfigMap 含 log4j 但未挂载 | 统一挂载 | ✅ |
| 10 | PCR `configs[]` 存在冗余 `templateRef` | 移除，对齐 redis/kafka/mysql PCR | ✅ |
| 11 | PCR 缺少 `annotations` | 新增 `hadoop.annotations` helper | ✅ |
| 12 | PCR `componentDef` 使用正则 | 改用文字名称 `hadoop-core` / `hdfs-*` | ✅ |
| 13 | PCR journalnode/namenode/datanode "同理"不充分 | ~~显式双条目~~ → **修正为单条目**（恢复 0.9 共享 ConfigMap 模式） | ✅ |
| 14 | **data 组件 cmdp 错误包含共享 ConfigMap** | **移除** hadoop-core-config 条目，恢复 0.9 模式 | ✅ |