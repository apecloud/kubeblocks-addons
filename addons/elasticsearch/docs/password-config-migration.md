# Elasticsearch 系统账号密码配置迁移

## 问题与范围

当前 KubeBlocks main 的 `apps.kubeblocks.io/v1` ComponentDefinition 使用
`spec.systemAccounts[].passwordConfig`。Elasticsearch 的公共模板仍输出
`passwordGenerationPolicy`；在只识别新字段的 CRD 上，旧字段不能传递密码生成策略。
新接口把未配置 `passwordConfig` 的账号视为无密码账号，因此不能依赖隐式默认值。

本次只迁移 ES 6/7/8 的普通、master、data 共九种 ComponentDefinition 中的
`elastic` 和 `kibana_system` 初始化账号。两者继续使用长度 10、数字 5、符号 0、
大小写混合的策略，账号名称和 `initAccount: true` 不变。Kibana 仍引用 ES 账号，
不新增自身账号。数据库版本、插件、生命周期脚本、拓扑和凭据传递流程不在修改范围内。

## 方案与版本

- 公共模板的两个字段改为 `passwordConfig`，保留原策略的全部取值。
- Chart 从 `1.2.0-alpha.0` 升至 `1.2.0-alpha.1`，沿用现有按 Chart.Version
  命名的规则，产生新的 ComponentDefinition 身份；不覆盖旧名称下的不可变账号结构。
- KubeBlocks 兼容标注收紧至 `>=1.2.0`，本次目标是使用新账号接口的 main/1.2 产品线。
  此标注是本次支持范围，不是字段最早引入版本或 Helm 客户端的运行时 CRD 检测。
  `passwordConfig` 在 release-1.1 已出现，并保留旧字段兼容；main/1.2 移除旧字段。
  本次 main chart 不承诺 1.0/1.1 产品线兼容。安装前必须确认 operator 和 CRD 配套。
- 默认的 `extra.keepResource: true` 继续保留旧定义；ComponentVersion 选择器继续
  匹配新旧版本化名称。未引入 `lookup`、双字段输出或不确定的在线探测。

## 存量兼容边界

本 PR 不提供存量集群自动迁移、密码轮换或凭据修复。已有集群应保留其正在引用的
ComponentDefinition 和账号 Secret。升级前核对实际 Component 使用的定义、
`extra.keepResource` 配置，以及各 ES/Kibana 组件的凭据引用；不要删除旧定义或
Secret 来强制切换。关闭资源保留的自定义安装不在默认保留保证内。

本次没有修改账号名称，也没有在 chart 中创建或覆盖账号 Secret。所核对的
KubeBlocks main 控制器在更新已有、非外部 Secret 引用的账号时保留现有密码数据。
这是源码核对结论，不代表已经验证任意存量集群的升级过程。如果旧字段曾被裁剪并
产生空密码 Secret，本次迁移不会自动修复；必须另行检查实际凭据和恢复方案。

## 离线回归

ShellSpec 渲染实际 chart，检查九种 ES 定义的全部 18 个账号、三个 Kibana 定义、
新定义身份、默认保留、ES/Kibana 凭据引用和新旧 ComponentVersion 匹配。
同时覆盖安装/升级渲染、registry/namespace 参数和未来 Chart.Version，避免仅测试模板文本。
另用当前上游 CRD 的账号 schema 核对渲染结果，并比较迁移前后渲染内容，确认除字段名、
版本化身份和 chart 标签外没有业务配置变化。本次不创建 Kubernetes 资源或 CT Run。

复现：

```bash
helm dependency build addons/elasticsearch
helm lint addons/elasticsearch
shellspec --load-path shellspec addons/elasticsearch/scripts-ut-spec/password_config_spec.sh
```

## 核对来源

- [KubeBlocks main 账号字段](https://github.com/apecloud/kubeblocks/blob/0e052f803c7e3b2301d70cff3563c4eb79d8cece/apis/apps/v1/componentdefinition_types.go)
- [同版本 ComponentDefinition CRD](https://github.com/apecloud/kubeblocks/blob/0e052f803c7e3b2301d70cff3563c4eb79d8cece/config/crd/bases/apps.kubeblocks.io_componentdefinitions.yaml)
- [同版本账号 Secret 更新路径](https://github.com/apecloud/kubeblocks/blob/0e052f803c7e3b2301d70cff3563c4eb79d8cece/controllers/apps/component/transformer_component_account.go)
- [KubeBlocks 1.0.2 的旧字段](https://github.com/apecloud/kubeblocks/blob/v1.0.2/apis/apps/v1/componentdefinition_types.go)

- [release-1.1 的新旧字段兼容定义](https://github.com/apecloud/kubeblocks/blob/8d933967e170a7d6112e1373d1907ab1c3fece6a/apis/apps/v1/componentdefinition_types.go)
