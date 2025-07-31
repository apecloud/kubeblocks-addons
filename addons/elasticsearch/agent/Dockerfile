FROM golang:1.21-alpine AS builder

WORKDIR /app

# 复制go mod文件
COPY go.mod go.sum ./

# 下载依赖
RUN go mod download

# 复制源代码
COPY main.go ./

# 构建应用
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o agent main.go

# 使用elasticsearch基础镜像，这样可以访问elasticsearch-keystore命令
FROM docker.io/elasticsearch:8.8.2

# 安装必要的工具
USER root
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# 复制agent二进制文件
COPY --from=builder /app/agent /usr/local/bin/agent

# 确保agent可执行
RUN chmod +x /usr/local/bin/agent

# 切换回elasticsearch用户
USER elasticsearch

# 暴露agent端口
EXPOSE 8080

# 启动agent
CMD ["/usr/local/bin/agent"]
