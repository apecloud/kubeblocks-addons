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
  {{- if and (index $external_meta_service.spec "endpoint") (index $external_meta_service.spec "port") }}
     {{- $etcd_endpoint = printf "%s:%s" $external_meta_service.spec.endpoint.value $external_meta_service.spec.port.value }}
  {{- end }}
{{- end }}

{{- $pulsar_server := printf "%s-pulsar-headless.%s.svc.cluster.local" $clusterName $namespace }}
{{- $pulsar_port := "6650" }}
{{- if $external_log_service }}
  {{- if index $external_log_service.spec "endpoint" }}
     {{- $pulsar_server = printf "%s" $external_log_service.spec.endpoint.value }}
  {{- end }}
  {{- if index $external_log_service.spec "port" }}
     {{- $pulsar_port = printf "%s" $external_log_service.spec.port.value }}
  {{- end }}
{{- end }}

{{- $minio_server := printf "%s-minio-headless.%s.svc.cluster.local" $clusterName $namespace }}
{{- $minio_port := "9000" }}
{{- if $external_object_service }}
  {{- if index $external_object_service.spec "endpoint" }}
     {{- $minio_server = printf "%s" $external_object_service.spec.endpoint.value }}
  {{- end }}
  {{- if index $external_object_service.spec "port" }}
     {{- $minio_port = printf "%s" $external_object_service.spec.port.value }}
  {{- end }}
  {{- if index $external_object_service.spec "auth" }}
    {{- if index $external_object_service.spec.auth "username" }}
       {{- $minioAccessKey = printf "%s" $external_object_service.spec.auth.username.value }}
    {{- end }}
    {{- if index $external_object_service.spec.auth "password" }}
       {{- $minioSecretKey = printf "%s" $external_object_service.spec.auth.password.value }}
    {{- end }}
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
