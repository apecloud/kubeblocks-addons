auth_enabled: false

{{ $storageType := getEnvByName ( index $.podSpec.containers 0 ) "STORAGE_TYPE" }}

server:
  grpc_listen_port: ${SERVER_GRPC_PORT}
  http_listen_port: ${SERVER_HTTP_PORT}
  grpc_server_max_recv_msg_size: 52428800

memberlist:
   bind_addr:
   - ${KB_POD_IP}
   join_members:
   - {{ .KB_CLUSTER_NAME }}-memberlist

common:
  compactor_address: '{{ .KB_CLUSTER_NAME }}-backend'
{{/*  compactor_grpc_address: '{{ printf "http://%s-backend.%s.svc.%s:9095" .KB_CLUSTER_NAME .KB_NAMESPACE .clusterDomain .KB_CLUSTER_NAME }}-backend' */}}
  path_prefix: /var/loki
  replication_factor: 1
  storage:
    {{- if eq $storageType "oss" }}
    alibabacloud:
      endpoint: ${ENDPOINT}
      access_key_id: ${ACCESS_KEY_ID}
      secret_access_key: ${SECRET_ACCESS_KEY}
      bucket: ${BUCKETNAMES}
    {{- else if eq $storageType "local" }}
    filesystem:
      chunks_directory: ${LOCAL_CHUNKS_DIR}
      rules_directory: ${LOCAL_RULES_DIR}
    {{- else }}
    s3:
      endpoint: ${ENDPOINT}
      region: ${REGION}
      access_key_id: ${ACCESS_KEY_ID}
      secret_access_key: ${SECRET_ACCESS_KEY}
      bucketnames: ${BUCKETNAMES}
      insecure: true
      s3forcepathstyle: true
    {{- end }}

storage_config:
  {{- if eq $storageType "oss" }}
  alibabacloud:
    endpoint: ${ENDPOINT}
    access_key_id: ${ACCESS_KEY_ID}
    secret_access_key: ${SECRET_ACCESS_KEY}
    bucket: ${BUCKETNAMES}
  {{- else if eq $storageType "local" }}
  filesystem:
    directory: ${LOCAL_CHUNKS_DIR}
  {{- else }}
  aws:
    endpoint: ${ENDPOINT}
    region: ${REGION}
    access_key_id: ${ACCESS_KEY_ID}
    secret_access_key: ${SECRET_ACCESS_KEY}
    bucketnames: ${BUCKETNAMES}
    insecure: true
    s3forcepathstyle: true
  {{- end }}

limits_config:
  ingestion_burst_size_mb: 100
  max_cache_freshness_per_query: 10m
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  retention_period: 48h
  split_queries_by_interval: 2h

{{/* runtime_config: */}}
{{/* file: {{ getVolumePathByName ( index $.podSpec.containers 0 ) "runtime-config" }}/runtime-config.yaml */}}

schema_config:
  configs:
  - from: "2022-01-11"
    index:
      period: 24h
      prefix: loki_index_
    {{- if eq $storageType "oss" }}
    object_store: alibabacloud
    {{- else if eq $storageType "local" }}
    object_store: filesystem
    {{- else }}
    object_store: s3
    {{- end }}
    schema: v12
    store: boltdb-shipper

ruler:
  storage:
    {{- if eq $storageType "oss" }}
    alibabacloud:
      bucket: ${RULER_BUCKETNAMES}
    {{- else if eq $storageType "local" }}
    local:
      directory: ${LOCAL_RULES_DIR}
    {{- else }}
    s3:
      bucketnames: ${RULER_BUCKETNAMES}
    {{- end }}
    {{- if eq $storageType "oss" }}
    type: alibabacloud
    {{- else if eq $storageType "local" }}
    type: local
    {{- else }}
    type: s3
    {{- end }}

compactor:
  apply_retention_interval: 1h
  compaction_interval: 5m
  retention_delete_worker_count: 500
  retention_enabled: true
  {{- if eq $storageType "oss" }}
  shared_store: alibabacloud
  {{- else if eq $storageType "local" }}
  shared_store: filesystem
  {{- else }}
  shared_store: s3
  {{- end }}

index_gateway:
  mode: ring

query_range:
  align_queries_with_step: true

tracing:
  enabled: false