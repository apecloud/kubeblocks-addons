{{- $mongodb_port_info := getPortByName ( index $.podSpec.containers 0 ) "mongodb" }}
{{- $metrics_port_info := getPortByName ( index $.podSpec.containers 1 ) "http-metrics" }}
{{- $telemetry_port_info := getPortByName ( index $.podSpec.containers 1 ) "http-telemetry" }}

# require port
{{- $mongodb_port := 27017 }}
{{- if $mongodb_port_info }}
{{- $mongodb_port = $mongodb_port_info.containerPort }}
{{- end }}

# require port
{{- $metrics_port := 9216 }}
{{- if $metrics_port_info }}
{{- $metrics_port = $metrics_port_info.containerPort }}
{{- end }}

# require port
{{- $telemetry_port := 8888 }}
{{- if $telemetry_port_info }}
{{- $telemetry_port = $telemetry_port_info.containerPort }}
{{- end }}

receivers:
  apecloudmongodb:
    endpoint: 127.0.0.1:{{ $mongodb_port }}
    username: ${env:MONGODB_ROOT_USER}
    password: ${env:MONGODB_ROOT_PASSWORD}
    connect_params: admin?ssl=false&authSource=admin
    collect_all: true
    collection_interval: 15s
    direct_connect: true
    global_conn_pool: false
    compatible_mode: true

processors:
  batch:
    timeout: 5s
  memory_limiter:
    limit_mib: 1024
    spike_limit_mib: 256
    check_interval: 10s

exporters:
  prometheus:
    endpoint: 0.0.0.0:{{ $metrics_port }}
    const_labels: [ ]
    send_timestamps: false
    metric_expiration: 30s
    enable_open_metrics: false
    resource_to_telemetry_conversion:
      enabled: true

service:
  telemetry:
    logs:
      level: info
    metrics:
      address: 0.0.0.0:{{ $telemetry_port }}
  pipelines:
    metrics:
      receivers: [apecloudmongodb]
      processors: [memory_limiter]
      exporters: [prometheus]

