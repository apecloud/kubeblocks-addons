# Rendered by the KubeBlocks config renderer.
# KubeBlocks restart marker for replication peer-list changes.
# DOLT_CLUSTER_MODE={{ default "false" (index . "DOLT_CLUSTER_MODE") }}
# DOLT_CLUSTER_REPLICAS={{ default "1" (index . "DOLT_CLUSTER_REPLICAS") }}
# DOLT_POD_FQDN_LIST={{ default "" (index . "DOLT_POD_FQDN_LIST") }}
{{- $dataDir := default "/var/lib/dolt" (index . "DOLT_DATA_DIR") }}
log_level: {{ default "info" .DOLT_LOG_LEVEL }}
log_format: {{ default "text" .DOLT_LOG_FORMAT }}
data_dir: {{ $dataDir }}
cfg_dir: {{ $dataDir }}/.doltcfg
privilege_file: {{ $dataDir }}/.doltcfg/privileges.db
branch_control_file: {{ $dataDir }}/.doltcfg/branch_control.db

behavior:
  read_only: {{ default "false" .DOLT_READ_ONLY }}
  autocommit: {{ default "true" .DOLT_AUTOCOMMIT }}
  dolt_transaction_commit: {{ default "false" .DOLT_TRANSACTION_COMMIT }}
  auto_gc_behavior:
    enable: {{ default "true" .DOLT_AUTO_GC_ENABLED }}

listener:
  host: 0.0.0.0
  port: {{ default 3306 .DOLT_SQL_PORT }}
  max_connections: {{ default "1000" .DOLT_MAX_CONNECTIONS }}
  back_log: {{ default "50" .DOLT_BACK_LOG }}
  max_connections_timeout_millis: {{ default "60000" .DOLT_MAX_CONNECTIONS_TIMEOUT_MILLIS }}
  read_timeout_millis: {{ default "28800000" .DOLT_READ_TIMEOUT_MILLIS }}
  write_timeout_millis: {{ default "28800000" .DOLT_WRITE_TIMEOUT_MILLIS }}
  require_secure_transport: {{ if eq (default "false" (index . "TLS_ENABLED")) "true" }}true{{ else }}false{{ end }}
{{ if eq (default "false" (index . "TLS_ENABLED")) "true" }}
  tls_cert: {{ default "/etc/pki/tls" .TLS_MOUNT_PATH }}/tls.crt
  tls_key: {{ default "/etc/pki/tls" .TLS_MOUNT_PATH }}/tls.key
  ca_cert: {{ default "/etc/pki/tls" .TLS_MOUNT_PATH }}/ca.crt
{{ end }}

metrics:
  host: {{ default "0.0.0.0" (index . "DOLT_METRICS_HOST") }}
  port: {{ default 11228 (index . "DOLT_METRICS_PORT") }}
  labels:
    namespace: "{{ default "" (index . "DOLT_METRICS_LABEL_NAMESPACE") }}"
    cluster: "{{ default "" (index . "DOLT_METRICS_LABEL_CLUSTER") }}"
    component: "{{ default "" (index . "DOLT_METRICS_LABEL_COMPONENT") }}"
