# reference: https://github.com/chengshiwen/influxdb-cluster/wiki/Configure-Data-Nodes
[coordinator]
  log-queries-after = "0s"

[meta]
  dir = "/var/lib/influxdb/meta"

[data]
  dir = "/var/lib/influxdb/data"
  engine = "tsm1"
  wal-dir = "/var/lib/influxdb/wal"

[hinted-handoff]
  dir = "/var/lib/influxdb/hh"

[http]
  enabled = true
  bind-address = ":8086"
  auth-enabled = true
{{- if eq (index . "TLS_ENABLED") "true" }}
  https-enabled = true
  https-certificate = "{{ .TLS_MOUNT_PATH }}/tls.crt"
  https-private-key = "{{ .TLS_MOUNT_PATH }}/tls.key"
{{- end }}
