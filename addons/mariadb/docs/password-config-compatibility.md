# MariaDB 在 KubeBlocks main 上保留密码生成配置

## 为什么修改

Run `tr-20261013183002193-b7e80b60` 使用 `apecloud/kubeblocks-addons@c309f306` 与 `apecloud/kubeblocks@64eb50cf`。原日志显示 MariaDB 首次初始化没有收到密码，容器反复退出，standalone T2 连接检查失败。证据附件 `dcb6cbab-e6ba-44a9-b77f-54be9ab2b0ab` 的 72 份共享文件已逐一核对 SHA256；历史实际 Pod 已被外层清理删除，不能再声称可以完整恢复其 env。

源码有一个确定的不兼容：MariaDB 的账号仍声明 `passwordGenerationPolicy`，而这版 KubeBlocks 的 SystemAccount 和 CRD 使用 `passwordConfig`。控制器把缺少 passwordConfig 解释为无密码账号。变量 `MARIADB_ROOT_PASSWORD` 本身仍通过 root 账号的 Secret 引用注入，不能靠在容器中补一个固定密码来修复。

另一个仓库 `apecloud/apecloud-addons` 的 PR2091 已于 2026-09-08 修复同类字段问题，合入为 `4fd485e6`。本轮明确使用的是 `apecloud/kubeblocks-addons`；其当前 main `720f2bec` 仍保留旧字段。两个仓库的修复状态不能混用。本次复用这一已确认的字段迁移思路，在实际使用的仓库补齐修复和独立回归。

## 修改范围

只把真实 Helm 渲染对象中账号的密码生成字段迁移为 `passwordConfig`，保留账号名称、initAccount、密码长度、数字/符号数量、大小写规则和 root Secret 引用。覆盖 standalone、replication、galera 三种组件的全部有效账号。先从真实安装和升级渲染确定有效位置，再比较完整对象，避免改到无关配置。

当前测试源码 c309f306 还包含两行 syncer registry 默认值修复，但该补丁未进入当前 main。后续候选从当前 main 开始，保留这两行现有测试前提，使下一轮仍能从 Chart 声明解析 syncer。Chart 源码生成新 commit/tree 后，重新固定请求来源；不悄悄切换到另一个 addon 仓库。

本次不引入明文密码，不修改已有 Secret，不改变复制、账户权限或启动脚本。针对的是本轮 KubeBlocks main 的实际 CRD；不声称已验证全部历史 KubeBlocks 版本。旧 Run 和其残留仅供只读取证，不做原地升级来掩盖失败。

## 验证方法

1. 保存未修改版本的完整 Helm 安装、升级渲染。用本轮 `64eb50cf` 的真实 ComponentDefinition CRD 检查账号字段，显式报告 API 会裁剪的未知字段；普通 JSON Schema 允许未知字段时也不能漏报。
2. 修复后逐账号验证 `passwordConfig` 及参数，核对 `MARIADB_ROOT_PASSWORD` 仍引用 root。完整渲染差异只能是预期字段迁移及此前已授权的 syncer registry 默认值。
3. 运行相关本地 Helm/脚本回归并记录准确结果；这不替代数据库运行测试。
4. 在保存的安装后 ComponentDefinition 中核对账号生成配置和现存工作负载模板的 Secret 引用。若历史 Pod 字段缺失，明确写出证据限制。
5. 与平台 PR705 的保留修复一起准备好后，用新请求键提交一次完整 standalone、async、galera 验证，核对数据库初始化、产品结果和最终资源清理。发现首个新失败先保存证据，不盲目重复提交。

## 镜像校验的独立解释

本轮镜像证据只冻结了 replication 组件的 init-syncer；实际仅运行 standalone，首错后未进入 replication。原 Component 的 owner 链完整，但其 ComponentDefinition 不属于冻结的 syncer consumer，所以记录为缺少实际组件观测。这不是已证实的镜像摘要错误；不能用跳过镜像校验来解决密码初始化失败。
