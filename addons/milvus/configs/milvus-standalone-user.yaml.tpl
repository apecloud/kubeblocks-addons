{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace   := $.cluster.metadata.namespace }}
{{- $minioAccessKey := getEnvByName ( index $.podSpec.containers 0 ) "MINIO_ACCESS_KEY" }}
{{- $minioSecretKey := getEnvByName ( index $.podSpec.containers 0 ) "MINIO_SECRET_KEY" }}

etcd:
  endpoints:
  - {{$clusterName}}-etcd-headless.{{$namespace}}.svc.cluster.local:2379
  rootPath: {{$clusterName}}
messageQueue: rocksmq
minio:
  address: {{$clusterName}}-minio-headless.{{$namespace}}.svc.cluster.local
  bucketName: {{$clusterName}}
  port: 9000
  accessKeyID: {{$minioAccessKey}}
  secretAccessKey: {{$minioSecretKey}}
msgChannel:
  chanNamePrefix:
    cluster: {{$clusterName}}
  rocksmq: {}
