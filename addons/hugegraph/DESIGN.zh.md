# HugeGraph 1.7.0 单节点 Addon 设计

## 1. 问题与证据

目标是在 KubeBlocks Addons `release-1.0` 上提供 HugeGraph 1.7.0 单节点
RocksDB addon，并支持整实例备份恢复。首版不能依赖 CSI VolumeSnapshot。

HugeGraph 1.7.0 提供 graph 级 RocksDB checkpoint API：

- `PUT /graphspaces/DEFAULT/graphs/{graph}/snapshot_create`
- `PUT /graphspaces/DEFAULT/graphs/{graph}/snapshot_resume`

`snapshot_create` 会为 graph 的 schema、system、graph 三类 RocksDB store 创建
checkpoint。checkpoint 位于原始 RocksDB 目录的同级 `snapshot_*` 目录。该行为在
HugeGraph 1.7.0 的 `GraphsAPI`、`AbstractBackendStoreProvider`、`RocksDBStore` 和
`RocksDBStdSessions` 中可追溯。

KubeBlocks `release-1.0` 的非 snapshot 数据保护链路通过
`BackupPolicyTemplate + ActionSet` 工作。`prepareData` Job 会把目标 PVC 挂载到
Backup method 声明的 mountPath，因此可以在目标 Pod 启动前把 checkpoint 写回新
PVC。

## 2. 范围

首版支持：

- HugeGraph Server 1.7.0，单副本，内嵌 RocksDB。
- HTTP 8080 和 Gremlin 8182 服务。
- `admin` init system account；探针和数据保护均使用该账号。
- 一个 `data` PVC，保存 graph 配置、RocksDB、WAL 和初始化标记。
- 对实例内所有持久化 graph 做 full checkpoint backup。
- 从 full checkpoint backup 恢复到同版本、同 topology 的新 Cluster。
- Restart、Stop/Start、VerticalScaling、VolumeExpansion 和 Expose 的底层合同。

首版不支持：

- CSI volume snapshot、PITR、增量备份、单 graph 选择性恢复。
- 多 graph 之间的全局事务时间点。每个 graph 自身 checkpoint 一致，但 graph 之间
  按顺序创建 checkpoint，存在短时间窗口。
- RebuildInstance、scaleOut.fromBackup、跨 HugeGraph 版本、跨 topology 恢复。
- TLS、在线参数变更、分布式 PD/Store/Server topology。

## 3. 存储和启动

PVC 固定挂载到 `/hugegraph-data`：

```text
/hugegraph-data/
  graphs/                 # 持久化 graph properties
  rocksdb/                # 默认 hugegraph 数据
  rocksdb_<graph>/        # clone graph 数据
  wal/                    # 默认 hugegraph WAL
  wal_<graph>/            # clone graph WAL
  docker/init_complete    # 上游 entrypoint 初始化标记
```

不把 PVC 覆盖到 `/hugegraph-server`，避免遮蔽镜像内二进制、插件和默认配置。
启动脚本执行以下动作后调用上游 `docker-entrypoint.sh`：

1. 首次启动时把默认 `hugegraph.properties` 复制到持久化 `graphs/`。
2. 把 `rest-server.properties` 的 `graphs` 指向持久化目录并监听 `0.0.0.0`。
3. 校验每个 graph 都使用 RocksDB，且 data/WAL 路径是 PVC 根目录的直接子目录。
4. 为每个 graph 启用 `HugeFactoryAuthProxy`。
5. 把上游 `docker/` 初始化标记目录链接到 PVC。

动态多图推荐使用 `clone_graph_name=hugegraph` 创建。HugeGraph 的 RocksDB provider
会为 clone graph 自动生成独立的 `rocksdb_<graph>` 和 `wal_<graph>` 路径。直接
创建 graph 时必须显式提供满足上述路径约束的 `rocksdb.data_path` 和
`rocksdb.wal_path`；否则备份前置检查会失败，不会静默漏备份。

## 4. 备份流程

Backup method 名为 `checkpoint`，`snapshotVolumes=false`。ActionSet 使用
`hugegraph/hugegraph:1.7.0`，不增加自建工具镜像。

1. 在 PVC 上获取原子目录锁，拒绝并发 checkpoint backup。
2. 枚举 `/hugegraph-data/graphs/*.properties`，至少要求一个 graph。
3. 校验 backend、store、RocksDB data/WAL 路径和认证代理。
4. 对每个 graph 调用 `snapshot_create`。
5. 枚举、限制并验证所有 `snapshot_*` 目录非空。
6. 生成 `manifest.properties` 和 `checksums.sha256`。
7. 上传 manifest、checksum 和 `payload.tar.gz` 到当前 datasafed backup path。
8. 更新 backup size；无论成功失败，只清理由本次流程记录的 checkpoint 和锁。

artifact format v1：

```text
manifest.properties
checksums.sha256
payload.tar.gz
  graphs/*.properties
  snapshot_*/...
  manifest.properties
  checksums.sha256
```

manifest 记录 format、engine/service version、graph 名和配置 hash、checkpoint source
和目标 RocksDB 目录。恢复必须拒绝未知 format、版本不一致、空 graph/checkpoint、
checksum 错误和越界路径。

## 5. 恢复流程

恢复在 `prepareData` 执行，不等待业务 Pod Ready：

1. 一次性拉取外层 manifest、checksum 和 payload，后续校验与解压使用同一份文件。
2. 先只列出 payload，拒绝绝对路径、`..`、链接和非白名单成员。
3. 流式解压到目标 PVC 内的隔离 staging 目录。
4. 比较内外 manifest/checksum，并执行 `sha256sum -c`。
5. 根据 graph config 验证 checkpoint 与 RocksDB data 目录一一对应，再把
   `snapshot_<origin>` 原子移动为 `<origin>`，并移动 `graphs/`。
6. 创建持久化 `docker/init_complete`，确保上游 entrypoint 不会对已恢复 RocksDB
   再执行初始化。
7. 先同步数据，再写入本次 backup 的完成标记并删除 staging。

恢复不在 `postReady` 调用 `snapshot_resume`。原因是新 Cluster 的 PVC 本来为空，
checkpoint 可以在启动前直接成为 RocksDB 原目录；这样 HugeGraph 第一次打开的就是
恢复数据，避免先以空库 Ready、再在线替换 auth/store 所产生的可见窗口和缓存风险。
`snapshot_resume` 保留为 HugeGraph 在线回退 API，不是首版新 Cluster restore 阶段。

prepareData 通过“进行中标记 + backup name”处理重试。只有标记属于同一个 backup 时
才允许清理由该次失败留下的目标目录；不删除未标记的现有业务目录。完成态重试会重新
校验每个 graph config 和已恢复 checkpoint 文件的 SHA-256，不只检查目录存在。

## 6. 账号兼容

默认 graph 的 auth 数据包含在 checkpoint 中。KubeBlocks `release-1.0` 会把 full
Backup 的加密 system-account metadata 传递给 restore，并重建目标 init-account
Secret，因此目标 `admin` Secret 应与源 backup 对应。运行验证必须同时检查 Secret
和实际 HTTP 登录；在获得 live evidence 前，这一点只作为版本锁定的控制器能力，
不扩展为跨版本保证。

## 7. 兼容性矩阵

| 场景 | 首版结论 |
| --- | --- |
| 新 Cluster，同 topology，1.7.0 -> 1.7.0 | 支持，需真实 backup/restore 验证 |
| 空 graph | 支持；checkpoint 仍必须包含 RocksDB 元数据文件 |
| 多 graph | 支持逐 graph checkpoint；不保证跨 graph 同一时间点 |
| TLS on/off | TLS 不声明支持 |
| RebuildInstance / scaleOut.fromBackup | 不支持 |
| 跨 serviceVersion / topology | 不支持，restore preflight 拒绝 |
| PITR / incremental / selective | 不支持 |

## 8. 测试计划

开发侧离线合同测试：

- `helm lint` 和 definition/cluster chart 的代表性 `helm template`。
- 名称、compDef、ActionSet、BPT、volume、service port、system account 引用闭合。
- 明确断言不存在 `volume-snapshot` 或 `snapshotVolumes: true`。
- Bash 语法、manifest/checksum、路径白名单、checkpoint 清理和恢复重试合同。
- restore example 固定单副本、1.7.0、目标 volume 与 source target 映射。

Tester 侧 live 验证由固定 HugeGraph tester 独立组包和执行，至少覆盖：单 graph、空
graph、多 graph、并发备份拒绝、checkpoint API 失败、artifact 缺失/checksum 损坏、
新 Cluster restore、恢复后读写、admin Secret/实际登录一致、Restart、Stop/Start、
VerticalScaling 和 VolumeExpansion。

## 9. 合同来源

- `kubeblocks-addon-docs/docs/addon-api/02-component-definition.md`
- `kubeblocks-addon-docs/docs/addon-api/03-cluster-definition.md`
- `kubeblocks-addon-docs/docs/addon-api/04-component-version.md`
- `kubeblocks-addon-docs/docs/addon-api/07-accounts-and-tls.md`
- `kubeblocks-addon-docs/docs/addon-api/09a-backup-basic.md`
- `kubeblocks-addon-docs/docs/addon-api/09b-backup-extensions.md`
- `kubeblocks-addon-docs/docs/addon-api/09c-restore-and-rebuild.md`
- `kubeblocks-addon-docs/docs/addon-api/10-day2-operations.md`
- `kubeblocks-addon-docs/docs/addon-api/12a-minimum-acceptance.md`
- `kubeblocks-addon-docs/docs/addon-api/12b-claimed-only-acceptance.md`
