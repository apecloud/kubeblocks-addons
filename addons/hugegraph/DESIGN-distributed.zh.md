# HugeGraph 1.7.0 分布式 Topology 设计

依据 `docs/addon-api/03-cluster-definition.md`、`06-variables-and-services.md`、
`12a-minimum-acceptance.md`、`12b-claimed-only-acceptance.md`。

## 1. 拓扑含义

`distributed` 是用户可选的第二种部署形态：PD + Store + Server。
这不是 sharding。PD / Store 的多副本是同一 Raft 组里的 `replicas`。

官方 1.7.0 运行时依赖是 PD healthy -> Store -> Server。
PD 启动又需要事先知道 Store 的稳定 FQDN 列表，所以对象创建上 PD 和 Store
放在同一 provision 阶段（逗号=并行），Server 后置。Store 启动脚本等 PD
`/v1/health`。这符合合同：阶段内并行、阶段间有序。

```text
orders.provision:  [pd,store, server]
orders.terminate: [server, store,pd]
orders.update:    [pd,store, server]
```

`standalone` 仍是唯一 default。未指定 topology 时必须落到 standalone。

## 2. 组件与名字

| topology component | CmpD 名 | 正则 | 镜像 |
| --- | --- | --- | --- |
| standalone `server` | `hugegraph-{{ ver }}` | `^hugegraph-[0-9]` | `hugegraph/hugegraph:1.7.0` |
| distributed `pd` | `hugegraph-pd-{{ ver }}` | `^hugegraph-pd-` | `hugegraph/pd:1.7.0` |
| distributed `store` | `hugegraph-store-{{ ver }}` | `^hugegraph-store-` | `hugegraph/store:1.7.0` |
| distributed `server` | `hugegraph-server-{{ ver }}` | `^hugegraph-server-` | `hugegraph/server:1.7.0` |

standalone 原来的 `^hugegraph-` 会误伤 `hugegraph-pd-` / `hugegraph-store-` /
`hugegraph-server-`，必须收窄。这是合同要求：`compDef` 正则要稳定命中唯一集合。

## 3. Raft 身份

官方用 hostname 当 Raft 成员 ID（`pd0:8610`）。合同要求不要把不可重算的
Pod 名 / clusterUID 写进引擎成员 ID。这里用 KB `podFQDNs` 生成
`{podFQDN}:port`，恢复或同名重建时只要 FQDN 规则不变就可以重算。

本节点地址从 `podFQDNs` 里按 `hostname` / `metadata.name` 前缀匹配，不手写
headless Service 名。

## 4. 本 PR 声明 / 不声明

声明：

- `distributed` topology 可渲染，orders 闭合
- 三组件 CmpD / ComponentVersion / example 名字对齐
- PD / Store / Server 用官方 `HG_*` 环境变量启动
- 最小规格：pd 3、store 3、server 1

不声明（12b，本轮不验收）：

- distributed backup / restore / PITR
- Store scale-in / rebalance
- PD / Store switchover、roleProbe
- TLS、reconfigure
- Hubble

BackupPolicyTemplate 继续只命中 standalone server CmpD。
