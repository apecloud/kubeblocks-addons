{{/*
Define replica count.
standalone mode: 1
replication mode: 2
raftGroup mode: 3 or more
*/}}
{{- define "mysql-cluster.replicaCount" -}}
replicas: {{  .Values.replicas.mysql  }}
{{- end -}}

{{- define "orchestrator.replicaCount" -}}
replicas: {{  .Values.replicas.orchestrator  }}
{{- end -}}
