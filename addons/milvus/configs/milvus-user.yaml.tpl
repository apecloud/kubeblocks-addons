{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace   := $.cluster.metadata.namespace }}
{{- $minioAccessKey := getEnvByName ( index $.podSpec.containers 0 ) "MINIO_ACCESS_KEY" }}
{{- $minioSecretKey := getEnvByName ( index $.podSpec.containers 0 ) "MINIO_SECRET_KEY" }}

{{- $external_meta_service := fromJson "{}" }}
{{- $external_log_service := fromJson "{}" }}
{{- $external_object_service := fromJson "{}" }}

{{- if index $.component "serviceReferences" }}
  {{- range $i, $e := $.component.serviceReferences }}
    {{- if eq $i "milvus-meta-storage" }}
      {{- $external_meta_service = $e }}
    {{- end }}
    {{- if eq $i "milvus-log-storage" }}
      {{- $external_log_service = $e }}
    {{- end }}
    {{- if eq $i "milvus-object-storage" }}
      {{- $external_object_service = $e }}
    {{- end }}
  {{- end }}
{{- end }}

{{- $etcd_endpoint := printf "%s-etcd-headless.%s.svc.cluster.local:2379" $clusterName $namespace }}
{{- if $external_meta_service }}
  {{- if index $external_meta_service.spec "endpoint" }}
     {{- $etcd_endpoint = printf "%s" $external_meta_service.spec.endpoint.value }}
  {{- end }}
{{- end }}

{{- $pulsar_server := printf "%s-pulsar-headless.%s.svc.cluster.local" $clusterName $namespace }}
{{- $pulsar_port := "6650" }}
{{- if $external_log_service }}
  {{- if index $external_log_service.spec "endpoint" }}
     {{- $pulsar_endpoint := printf "%s" $external_log_service.spec.endpoint.value }}
     {{- $parts := splitList ":" $pulsar_endpoint }}
     {{- if eq (len $parts) 2 }}
       {{- $pulsar_server = index $parts 0 }}
       {{- $pulsar_port = index $parts 1 }}
     {{- else if eq (len $parts) 1 }}
       {{- $pulsar_server = index $parts 0 }}
     {{- end }}
  {{- end }}
  {{- if index $external_log_service.spec "port" }}
     {{- $pulsar_port = printf "%s" $external_log_service.spec.port.value }}
  {{- end }}
{{- end }}

{{- $minio_server := printf "%s-minio-headless.%s.svc.cluster.local" $clusterName $namespace }}
{{- $minio_port := "9000" }}
{{- if $external_object_service }}
  {{- if index $external_object_service.spec "endpoint" }}
     {{- $minio_endpoint := printf "%s" $external_object_service.spec.endpoint.value }}
     {{- $parts := splitList ":" $minio_endpoint }}
     {{- if eq (len $parts) 2 }}
       {{- $minio_server = index $parts 0 }}
       {{- $minio_port = index $parts 1 }}
     {{- else if eq (len $parts) 1 }}
       {{- $minio_server = index $parts 0 }}
     {{- end }}
  {{- end }}
  {{- if index $external_object_service.spec "port" }}
     {{- $minio_port = printf "%s" $external_object_service.spec.port.value }}
  {{- end }}
{{- end }}

etcd:
  endpoints:
    - {{$etcd_endpoint}}
  rootPath: {{$clusterName}}
messageQueue: pulsar
minio:
  address: {{$minio_server}}
  port: {{$minio_port}}
  accessKeyID: {{$minioAccessKey}}
  secretAccessKey: {{$minioSecretKey}}
  bucketName: {{$clusterName}}
mq:
  type: pulsar
msgChannel:
  chanNamePrefix:
    cluster: {{$clusterName}}
pulsar:
  address: {{$pulsar_server}}
  port: {{$pulsar_port}}
