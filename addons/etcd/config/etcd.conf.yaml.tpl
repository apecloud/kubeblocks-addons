# https://github.com/etcd-io/etcd/blob/main/etcd.conf.yml.sample
# using this config file will ignore ALL command-line flag and environment variables.

{{- $peer_protocol := "http" }}
{{- $client_protocol := "http" }}
{{- if and $.component.tlsConfig (eq .PEER_TLS "true") }}
  {{- $peer_protocol = "https" }}
{{- end }}
{{- if and $.component.tlsConfig (eq .CLIENT_TLS "true") }}
  {{- $client_protocol = "https" }}
{{- end }}

# Human-readable name for this member.
name: 'default'

# Path to the data directory.
data-dir: {{ .DATA_DIR }}

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

# List of comma separated URLs to listen on for peer traffic.
listen-peer-urls: {{ $peer_protocol }}://0.0.0.0:2380

# List of comma separated URLs to listen on for client traffic.
listen-client-urls: {{ $client_protocol }}://0.0.0.0:2379

# Maximum number of snapshot files to retain (0 is unlimited).
max-snapshots: 5

# Maximum number of wal files to retain (0 is unlimited).
max-wals: 5

# Comma-separated white list of origins for CORS (cross-origin resource sharing).
cors:

# List of this member's peer URLs to advertise to the rest of the cluster.
# The URLs needed to be a comma-separated list.
initial-advertise-peer-urls: {{ $peer_protocol }}://0.0.0.0:2380

# List of this member's client URLs to advertise to the public.
# The URLs needed to be a comma-separated list.
advertise-client-urls: {{ $client_protocol }}://0.0.0.0:2379

# Discovery URL used to bootstrap the cluster.
discovery:

# Valid values include 'exit', 'proxy'
discovery-fallback: 'proxy'

# HTTP proxy to use for traffic to discovery service.
discovery-proxy:

# DNS domain used to bootstrap initial cluster.
discovery-srv:

{{- define "init_peers" }}
  {{- $peer_protocol := "http" }}
  {{- if and $.component.tlsConfig (eq .PEER_TLS "true") }}
    {{- $peer_protocol = "https" }}
  {{- end }}
  {{- if (index . "PEER_ENDPOINT") }}
    {{- $endpoints := splitList "," .PEER_ENDPOINT }}
    {{- range $idx, $endpoint := $endpoints }}
      {{- if $idx -}},{{- end }}
      {{- $hostname := index (splitList ":" $endpoint) 0 }}
      {{- if contains ":" $endpoint }}
        {{- $ip := index (splitList ":" $endpoint) 1 }}
        {{- printf "%s=%s://%s:2380" $hostname $peer_protocol $ip }}
      {{- else }}
        {{- printf "%s=%s://%s:2380" $hostname $peer_protocol $hostname }}
      {{- end }}
    {{- end }}
  {{- else if .PEER_FQDNS }}
    {{- $peerfqdns := splitList "," .PEER_FQDNS }}
    {{- range $idx, $fqdn := $peerfqdns }}
      {{- if $idx -}},{{- end }}
      {{- $hostname := index (splitList "." $fqdn) 0 }}
      {{- printf "%s=%s://%s:2380" $hostname $peer_protocol $fqdn }}
    {{- end }}
  {{- end }}
{{- end }}

# Comma separated string of initial cluster configuration for bootstrapping.
# Example: initial-cluster: "infra0=http://10.0.1.10:2380,infra1=http://10.0.1.11:2380,infra2=http://10.0.1.12:2380"
initial-cluster: {{ template "init_peers" . }}

# Initial cluster token for the etcd cluster during bootstrap.
initial-cluster-token: 'etcd-cluster'

# Initial cluster state ('new' or 'existing').
initial-cluster-state: 'new'

# Reject reconfiguration requests that would cause quorum loss.
strict-reconfig-check: true

# Enable runtime profiling data via HTTP server
enable-pprof: true

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

{{ if $.component.tlsConfig -}}
{{- $ca := getCAFile }}
{{- $cert := getCertFile }}
{{- $key := getKeyFile }}
{{- if eq $client_protocol "https" }}
client-transport-security:
  # Path to the client server TLS cert file.
  cert-file: {{ $cert }}

  # Path to the client server TLS key file.
  key-file: {{ $key }}

  # Enable client cert authentication.
  client-cert-auth: true

  # Path to the client server TLS trusted CA cert file.
  trusted-ca-file: {{ $ca }}

  # Client TLS using generated certificates
  auto-tls: false
{{- end }}
{{ if eq $peer_protocol "https" }}
peer-transport-security:
  # Path to the peer server TLS cert file.
  cert-file: {{ $cert }}

  # Path to the peer server TLS key file.
  key-file: {{ $key }}

  # Enable peer client cert authentication.
  client-cert-auth: true

  # Path to the peer server TLS trusted CA cert file.
  trusted-ca-file: {{ $ca }}

  # Peer TLS using generated certificates.
  auto-tls: false

  # Allowed CN for inter peer authentication.
  allowed-cn:

  # Allowed TLS hostname for inter peer authentication.
  allowed-hostname:
{{- end }}
{{- end }}

# The validity period of the self-signed certificate, the unit is year.
self-signed-cert-validity: 1

# Enable info-level logging for etcd.
log-level: info

logger: zap

# Specify 'stdout' or 'stderr' to skip journald logging even when running under systemd.
log-outputs: [stderr]

# Force to create a new one member cluster.
force-new-cluster: false

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

# Enable to check data corruption before serving any client/peer traffic.
experimental-initial-corrupt-check: true