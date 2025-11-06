# This is the configuration file for the etcd server.

# ========== immutableParameters, control by scripts ==========
# Human-readable name for this member.
name:

# Path to the data directory.
data-dir: {{ .DATA_DIR }}

# List of comma separated URLs to listen on for peer traffic.
listen-peer-urls: http://0.0.0.0:2380
# List of comma separated URLs to listen on for client traffic.
listen-client-urls: http://0.0.0.0:2379

# List of this member's peer URLs to advertise to the rest of the cluster.
# The URLs needed to be a comma-separated list.
initial-advertise-peer-urls:
# List of this member's client URLs to advertise to the public.
# The URLs needed to be a comma-separated list.
advertise-client-urls:

# Comma separated string of initial cluster configuration for bootstrapping.
# Example: initial-cluster: "infra0=http://10.0.1.10:2380,infra1=http://10.0.1.11:2380,infra2=http://10.0.1.12:2380"
initial-cluster:
# Initial cluster token for the etcd cluster during bootstrap.
initial-cluster-token: 'etcd-cluster'

# TLS configuration
client-transport-security:
peer-transport-security:

# ========== staticParameters, user can specify ==========
# Path to the dedicated wal directory.
wal-dir:

# Number of committed transactions to trigger a snapshot to disk.
snapshot-count: 10000
# Time (in milliseconds) of a heartbeat interval.
heartbeat-interval: 100
# Time (in milliseconds) for an election to timeout.
election-timeout: 1000
# Raise alarms when backend size exceeds the given quota. 0 means use the
# default quota.
quota-backend-bytes: 0
# Reject reconfiguration requests that would cause quorum loss.
strict-reconfig-check: false
# Maximum number of snapshot files to retain (0 is unlimited).
max-snapshots: 5
# Maximum number of wal files to retain (0 is unlimited).
max-wals: 5

# Auto compaction
auto-compaction-mode: periodic
auto-compaction-retention: "1"

# Limit etcd to a specific set of tls cipher suites
cipher-suites: [
  TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
  TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
]

# Limit etcd to specific TLS protocol versions
tls-min-version: 'TLS1.2'
tls-max-version: 'TLS1.3'

# Valid values include 'on', 'readonly', 'off'
proxy: 'off'
# Time (in milliseconds) an endpoint will be held in a failed state.
proxy-failure-wait: 5000
# Time (in milliseconds) of the endpoints refresh interval.
proxy-refresh-interval: 30000
# Time (in milliseconds) for a dial to timeout.
proxy-dial-timeout: 1000
# Time (in milliseconds) for a write to timeout.
proxy-write-timeout: 5000
# Time (in milliseconds) for a read to timeout.
proxy-read-timeout: 0

# Enable runtime profiling data via HTTP server
enable-pprof: false 

# Comma-separated white list of origins for CORS (cross-origin resource sharing).
cors:

# Discovery URL used to bootstrap the cluster.
discovery:
# Valid values include 'exit', 'proxy'
discovery-fallback: 'proxy'
# HTTP proxy to use for traffic to discovery service.
discovery-proxy:
# DNS domain used to bootstrap initial cluster.
discovery-srv:

# The validity period of the self-signed certificate, the unit is year.
self-signed-cert-validity: 1

# Enable debug-level logging for etcd.
log-level: info
logger: zap
# Specify 'stdout' or 'stderr' to skip journald logging even when running under systemd.
log-outputs: [stderr]

# Initial cluster state ('new' or 'existing').
initial-cluster-state: 'new'
# Force to create a new one member cluster.
force-new-cluster: false
