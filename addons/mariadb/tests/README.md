# MariaDB 密码配置回归

`test_password_config.py` 在临时目录构建 Chart 依赖，分别执行真实 Helm 安装和升级渲染。它核对三种组件的六个账号、root Secret 引用、syncer 镜像声明，并使用目标 KubeBlocks 的真实 CRD 验证账号字段及参数。未知字段必须报错，避免 JSON Schema 默认允许额外字段而漏掉 Kubernetes 裁剪。

依赖：Helm 3、Python 3、PyYAML、jsonschema。指定实际目标版本的 CRD，不从网络隐式取 latest：

```sh
python3 -m venv /tmp/mariadb-schema-venv
/tmp/mariadb-schema-venv/bin/pip install PyYAML jsonschema
git -C /path/to/kubeblocks show 64eb50cfc0a6aaf593ea5e145a03f5f1590a9edc:config/crd/bases/apps.kubeblocks.io_componentdefinitions.yaml > /tmp/mariadb-target-crd.yaml
/tmp/mariadb-schema-venv/bin/python addons/mariadb/tests/test_password_config.py --crd /tmp/mariadb-target-crd.yaml
```

可选 `--render-output DIR` 保存完整渲染结果作差异检查。测试不创建数据库，也不证明运行时密码注入或历史版本兼容；实际运行验证仍由平台完成。
