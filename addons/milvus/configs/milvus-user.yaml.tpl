{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace   := $.cluster.metadata.namespace }}
{{- $userName := getEnvByName ( index $.podSpec.containers 0 ) "MINIO_ACCESS_KEY" }}
{{- $secret := getEnvByName ( index $.podSpec.containers 0 ) "MINIO_SECRET_KEY" }}

etcd:
  endpoints:
  - {{$clusterName}}-etcd-headless.{{$namespace}}.svc.cluster.local:2379
  rootPath: {{$clusterName}}
messageQueue: pulsar
minio:
  accessKeyID: minioadmin
  address: {{$clusterName}}-minio-headless.{{$namespace}}.svc.cluster.local
  bucketName: {{$clusterName}}
  port: 9000
  secretAccessKey: minioadmin
mq:
  type: pulsar
msgChannel:
  chanNamePrefix:
    cluster: {{$clusterName}}
pulsar:
  address: {{$clusterName}}-pulsar-headless.{{$namespace}}.svc.cluster.local
  port: 6650