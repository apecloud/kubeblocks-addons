# SeaweedFS addon 首版设计

## 问题与目标

KubeBlocks 与 kubeblocks-addons 的 `release-1.0` 当前没有 SeaweedFS addon。用户需要用 KubeBlocks 创建和管理 S3 对象存储，要求参考 MinIO、RustFS。SeaweedFS 把卷定位、对象数据、目录元数据和 S3 协议分成不同进程，因此需要分别建模，保证启动依赖和数据卷都能闭合。

首版交付可审查的 chart、创建及常用运维示例、离线单元检查。集群实测通过前，不把任何功能写成已验收，也不宣称生产可用。

## 源码与契约依据

| 来源 | 固定版本 | 用途 |
| --- | --- | --- |
| KubeBlocks | release-1.0 / `7129ad3dc49aeb9edbd0a714e3ad11f1837ac6e8` | API、CRD 与后续测试目标 |
| kubeblocks-addons | release-1.0 / `3c873a8b541d80972d2533fefe8ee745eee1bf11` | 实现基线；参考 `addons/minio` |
| RustFS 参考 | main / `2865430cb8783646c98c61f67d1381b760a0c476` | 参考账号、脚本挂载、版本映射、危险缩容拒绝；不将 main 合入 1.0 |
| SeaweedFS | `4.47` / `c5073360007d28385a33426a42ac3e4ec504c5a3` | 上游正式版；核对参数、健康检查、认证和持久化 |

设计遵守 [addon-api 契约](https://github.com/apecloud/kubeblocks-addon-docs/tree/96f3ec13e76daac8c08a98f7adbd23f3f9535f61/docs/addon-api)：01 工作边界、02 组件、03 拓扑、04 版本、05 生命周期、06 服务和变量、07 账号、10 运维、12a/12b 验收。特别是：不能仅凭 Pod Ready 宣称业务可用；不能把数据迁移藏进 memberLeave；没有运行证据的能力必须注明未验证。

上游证据：`weed/command/{master,volume,filer,s3}.go` 定义四类进程参数；`docker/filer.toml` 使用 LevelDB2；`weed/s3api/auth_credentials.go` 从 AWS 两个环境变量创建管理身份；`weed/server/raft_server_handlers.go` 给出 master 状态接口。

## 组件与拓扑

| 组件 | 持久化 | standalone | distributed |
| --- | --- | --- | --- |
| master（卷定位与选主） | `/data/master` | 固定 1 副本 | 固定 3 副本，原生 Raft 选主 |
| volume（对象数据） | `/data/volume` | 固定 1 副本 | 至少 2 副本，示例 3 副本，可扩出；禁止直接缩入 |
| filer（目录、桶和对象元数据） | `/data/filer` 的 LevelDB2 | 固定 1 副本 | 固定 1 副本 |
| s3（客户端入口） | 无状态 | 1～32 副本 | 1～32 副本，示例 2 副本 |

默认 topology 为 `standalone`，适合先验证最小链路。`distributed` 表示拆分并增加 master、volume、S3 实例；由于 filer 仍为单副本，不称为完整 HA。两种拓扑用独立的 master/volume ComponentDefinition 固定副本边界；filer、S3 共享定义。

对象数据副本策略：standalone 为 `000`（单份），distributed 为 `001`（同机架内两个不同 volume server 各存一份）。分布式示例要求 volume Pod 分散到不同 Kubernetes 节点，但首版不承诺跨可用区容灾。扩出增加新数据的容量，不自动均衡旧数据。

创建与更新顺序：master → volume → filer → s3。删除顺序相反。master 的 Pod 并行创建，避免等待首个 Pod 选出 leader 才创建另外两台的死锁；Pod 更新逐个进行，follower 的 updatePriority 为 1、leader 为 2（先更新 follower）。

## 主要实现

- `addons/seaweedfs`：Chart、values/schema、六个 ComponentDefinition、一个 ClusterDefinition、版本资源、脚本与 filer 配置模板、README、代码级测试。
- `addons-cluster/seaweedfs`：创建集群的 chart，暴露拓扑、资源和 PVC 参数，并校验固定副本约束。
- `examples/seaweedfs`：两种创建拓扑、Restart、Stop/Start、VerticalScaling、VolumeExpansion、S3 扩缩容、volume 扩出样例。
- 仅使用 KubeBlocks 1.0 已存在的字段，不引入额外 operator、自制选主协议或业务 Pod 的 Kubernetes 写权限。

所有 definition 名称、脚本和配置名称通过带 seaweedfs 前缀的 helper 生成。脚本与配置带 chart 版本，避免新 chart 悄悄替换旧 definition 对应的启动逻辑。ComponentVersion 为每类定义映射同一个明确的 SeaweedFS 镜像 tag；`serviceVersion` 使用语义版本 `4.47.0`，镜像 tag 保留上游 `4.47`。

## 核心流程

1. KubeBlocks 通过 componentVarRef 提供实际 Pod FQDN 列表。启动脚本从列表中按当前 Pod 名找到自身，不猜 ordinal，也不硬编码 cluster.local。
2. master 启动时恢复已有 Raft 数据；三副本模式使用完整 peer 列表，单副本使用上游 `-peers=none`。不删除或重新格式化已有目录。
3. volume 获取 master 列表，通过原生心跳注册。filer 获取同一 master 列表，把 LevelDB2 元数据存入 PVC。S3 通过 filer 的 HTTP/gRPC Service 访问元数据和数据。
4. S3 初始化账号使用 KubeBlocks `systemAccounts` 和 `credentialVarRef` 注入 `AWS_ACCESS_KEY_ID`、`AWS_SECRET_ACCESS_KEY`。缺任一变量即退出，防止静默进入匿名模式。secret 不写 ConfigMap、命令参数或 addon 日志。
5. 使用上游 HTTP 健康接口作为 readiness；startup/liveness 只检查本地监听，避免远端故障导致健康进程被反复杀死。master roleProbe 从本机 `/cluster/status` 读取 leader/follower；未知响应不能报健康角色。
6. volume 的 memberLeave 明确失败，提示先迁移数据；首版不实现自动排空。不要对 master/filer 在线改变副本数。

## 兼容性与限制

- 全新 addon，无旧 SeaweedFS chart 原地迁移承诺。已有 MinIO/RustFS 的数据和账号不会自动转换；跨引擎迁移另做 S3 数据搬迁。
- 只固定一个上游引擎版本。跨版本升级、在线参数修改、TLS、备份恢复、PITR、Rebuild、自动切主操作和跨拓扑迁移不在首版支持范围。
- S3 是业务入口。master、volume、filer 内部接口未加认证，只适合受信任网络；不能向不可信客户端暴露内部服务。S3 健康 URL 只代表进程能响应，真实可用性以认证后对象读写为准。
- 密码由环境变量载入。凭据变更需要重启全部 S3 实例，不承诺热更新。
- volume 复制不保护 filer 元数据；单个 filer PVC 丢失可能导致整个对象命名空间不可恢复。
- VolumeExpansion 取决于 StorageClass 和 CSI；首版不做快照备份声明。
- master/volume/filer 的在线磁盘删除和带数据缩入禁止作为普通运维操作；示例默认保留防误删策略，删除数据需用户明确选择终止策略。

## 测试计划与交接

开发侧先写行为测试，再实现脚本：非连续 Pod 名、自定义 DNS 后缀、缺依赖、重复启动保留数据、无凭据拒绝启动、认证值不泄露、leader/follower/未知响应、volume 缩入拒绝。离线渲染检查覆盖两个 topology、所有引用、容器镜像、端口、PVC、不同 release/namespace、registry 覆盖、非法 values 和 KubeBlocks 1.0 CRD schema。

测试负责人负责打包、远端专属 vcluster、部署和运行取证。验收顺序为：definition Available → 两拓扑创建 → S3 认证正反例 → 桶/对象/分段上传和校验 → 重启、停止启动、资源/PVC 调整后数据保留 → S3 扩缩容、volume 扩出与缩入拒绝 → 分布式 master/volume 单 Pod 故障。每个宣称能力都需真实业务读写，首个产品失败立即保留现场并交开发定位。

测试环境尚未建立基线。KB/addon 精确提交已固定；tests/vcluster/syncer 版本由测试负责人确认并写入候选清单后才能运行。发布前需要固定候选的完整测试轮次和长测，不把本次离线检查当成发布验收。
