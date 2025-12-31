FROM golang:1.23-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY main.go ./

# Build application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o agent main.go

# Use elasticsearch base image to access elasticsearch-keystore command
FROM docker.io/elasticsearch:8.8.2

# Install necessary tools
USER root
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy agent binary
COPY --from=builder /app/agent /usr/local/bin/agent

# Make agent executable
RUN chmod +x /usr/local/bin/agent

# Switch back to elasticsearch user
USER elasticsearch

# Expose agent port
EXPOSE 8080

# Start agent
CMD ["/usr/local/bin/agent"]
