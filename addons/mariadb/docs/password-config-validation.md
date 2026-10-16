# MariaDB 密码配置修复验证

设计：[DOC-161@v1](https://infracreate.com/project-manager/designs/dd142fef-4ebb-4eaa-a33d-33e9b6ad6153?revisionNo=1)，2026-10-13 19:27:30Z 发布，早于代码修改。

## 失败证据与修改

失败 Run `tr-20261013183002193-b7e80b60` 使用 addon `c309f30689ed90d89e34f27b440ec10042669dbb` 和 KubeBlocks `64eb50cfc0a6aaf593ea5e145a03f5f1590a9edc`。MariaDB 原日志报初始化没有密码。原始业务归档 SHA256 为 `e68c2df147af8adb8973148f7d2aa237314fcddedf7264c0d329bf727127a5b4`，脱敏分享包的 72 份文件已按清单核验。

Athena 的只读快照（消息 `14198ffa-2d40-49e4-b2aa-95dbf1fb402a`，附件 `94439570-3ecf-414d-9fad-9e85693bc4b8`）显示：安装后的 standalone ComponentDefinition UID `fde4dd5d-98eb-44f3-abe6-651d0efbb8af` 两个账号都只剩 name/initAccount，没有密码生成配置。现存 InstanceSet 模板仍通过 account-root Secret 的 password 键注入 `MARIADB_ROOT_PASSWORD`。没有读取密码值；历史 Pod 已删除，快照不能替代当时 Pod.env。

本修复以实际使用仓库 `apecloud/kubeblocks-addons` 的 main `720f2becfdf8b57f744aae1f3d5b35f7fc0d9421` 为基线，只迁移三种组件中六个有效账号的生成字段，保留参数和引用。另外带回旧测试源 c309f306 已有的两行 syncer registry 默认值，使新的精确源码候选保留该测试前提。两个未被模板调用的旧 helper 没有改变。

## 本地验证

- 新回归在未改产品代码的 main 上失败：安装/升级各六个账号包含目标 CRD 不支持的 `passwordGenerationPolicy`；六组完整账号比较失败。root 凭据引用检查通过。该基线还缺少旧测试源已有的 syncer registry。
- 修复后 `tests/test_password_config.py --crd <64eb50cf ComponentDefinition CRD>` 四项测试通过。包含真实 Helm 安装和升级、六账号参数、目标 CRD 的类型/范围及未知字段检查、root 凭据引用和 syncer 镜像声明。
- 保存并比较安装与升级各 16 个完整 YAML 对象：将基线六个账号字段改名后，全部对象与修复版相同；没有其他渲染差异。默认 registry 均为 docker.io，所以补回显式 syncer registry 不改变默认渲染。
- 两个相关 ShellSpec 文件（galera_account_provision、replication_user_convergence）共 25 项通过，使用仓库要求的 `--load-path ./shellspec`。最初未指定该参数时未能加载 spec_helper，未执行测试；该启动错误单独留存。
- `git diff --check` 通过。实际数据库测试未在本机执行。

证据保存在工作区 `work/mariadb-platform-retest-20261013/pr702-live/password-*`，包含基线与修复测试日志、目标 CRD、完整渲染和比较结果。复现命令见 `../tests/README.md`。

## 仍需运行验证

本地结果证明字段符合本轮目标 CRD，不证明所有历史 KubeBlocks 版本兼容，也不等于数据库可连接。平台 PR705 修复另一处失败现场保留契约，已合并为 `6955bde30fe6989da6b35754ca95a1711c6ff0a3`，需实际发布后，再以此 addon 新提交执行完整 standalone、async、galera 测试并核对清理。原 Run、其终态与残留均保持不变。
