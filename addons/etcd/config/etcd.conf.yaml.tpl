# etcd server configuration file

# ========== immutableParameters ==========
# Node name
name:

# Data directory
data-dir: {{ .DATA_DIR }}

# Network listening
listen-peer-urls: http://0.0.0.0:2380
listen-client-urls: http://0.0.0.0:2379

# Network advertising
initial-advertise-peer-urls:
advertise-client-urls:

# Cluster initialization
initial-cluster:
initial-cluster-token: 'etcd-cluster'

# TLS configuration
client-transport-security:
peer-transport-security:

# ========== staticParameters, cluster will restart after change ==========
# WAL directory
wal-dir:

# Snapshot settings
snapshot-count: 10000
heartbeat-interval: 100
election-timeout: 1000
quota-backend-bytes: 0
strict-reconfig-check: false
max-snapshots: 5
max-wals: 5

# Auto compaction
auto-compaction-mode: periodic
auto-compaction-retention: "1"

# TLS cipher suites
cipher-suites: [
  TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
  TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
]

# TLS protocol versions
tls-min-version: 'TLS1.2'
tls-max-version: 'TLS1.3'

# Proxy settings
proxy: 'off'
proxy-failure-wait: 5000
proxy-refresh-interval: 30000
proxy-dial-timeout: 1000
proxy-write-timeout: 5000
proxy-read-timeout: 0

# Runtime profiling
enable-pprof: false 

# CORS settings
cors:

# Discovery settings
discovery:
discovery-fallback: 'proxy'
discovery-proxy:
discovery-srv:

# Certificate validity
self-signed-cert-validity: 1

# Logging
log-level: info
logger: zap
log-outputs: [stderr]

# Cluster management
initial-cluster-state: 'new'
force-new-cluster: false
