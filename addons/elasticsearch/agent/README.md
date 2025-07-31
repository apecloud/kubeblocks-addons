# Elasticsearch Agent

这个agent为Elasticsearch集群提供了简化的备份解决方案，通过HTTP API为节点设置S3凭证。

## 功能特性

1. **简单的keystore设置**: 通过HTTP API为本地节点设置S3访问凭证
2. **认证支持**: 支持Elasticsearch集群的认证机制
3. **轻量级**: 只专注于keystore设置，保持最大的灵活性

## API接口

### 健康检查
```
GET /health
```

### 设置Keystore
```
POST /keystore
Content-Type: application/json

{
  "access_key_id": "your-access-key",
  "secret_access_key": "your-secret-key"
}
```

## 工作流程

1. **备份脚本执行**: backup.sh脚本开始执行
2. **获取集群节点**: 脚本调用Elasticsearch `/_nodes` API获取所有节点信息
3. **设置Keystore**: 脚本为每个节点调用agent的`/keystore` API设置S3凭证
4. **重新加载安全设置**: 脚本调用 `/_nodes/reload_secure_settings` API
5. **继续备份流程**: 脚本继续执行原有的备份逻辑

## 部署配置

Agent作为sidecar容器部署在每个Elasticsearch pod中，配置如下：

### 环境变量
- `ELASTIC_USERNAME`: Elasticsearch用户名（如果启用认证）
- `ELASTIC_PASSWORD`: Elasticsearch密码（如果启用认证）
- `AGENT_PORT`: Agent监听端口（默认8080）

### 卷挂载
- `/usr/share/elasticsearch/bin`: Elasticsearch二进制文件目录
- `/usr/share/elasticsearch/config`: Elasticsearch配置目录
- `/usr/share/elasticsearch/data`: Elasticsearch数据目录

## 使用方法

现在只需要一个命令就可以完成备份：

```bash
# 一步完成keystore设置和备份
kubectl create backup my-backup --backup-method full-backup
```

## 构建和部署

### 构建Agent镜像
```bash
cd addons/elasticsearch/agent
./build.sh
```

### 推送镜像
```bash
./build.sh push
```

## 故障排除

### 常见问题

1. **Agent无法启动**
   - 检查镜像是否正确构建和推送
   - 检查环境变量配置
   - 查看pod日志: `kubectl logs <pod-name> -c agent`

2. **Keystore设置失败**
   - 检查elasticsearch-keystore命令是否可用
   - 检查卷挂载是否正确
   - 检查文件权限

3. **节点间通信失败**
   - 检查网络连接
   - 检查认证配置

### 日志查看
```bash
# 查看agent日志
kubectl logs <pod-name> -c agent

# 查看备份日志
kubectl logs <backup-job-pod>
```

## 安全考虑

1. **认证**: Agent支持与Elasticsearch相同的认证机制
2. **网络**: Agent仅在集群内部通信
3. **凭证**: S3凭证仅在内存中临时存储，不持久化
4. **权限**: Agent以非root用户运行，具有最小权限

## 性能优化

1. **轻量级**: Agent只处理keystore设置，资源消耗极小
2. **超时控制**: 所有HTTP请求都有合理的超时设置
3. **资源限制**: 建议为agent容器设置适当的资源限制

## 监控和告警

Agent提供健康检查接口，可以集成到监控系统中：

```bash
# 健康检查
curl http://<pod-ip>:8080/health
