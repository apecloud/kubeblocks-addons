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

{{/*
Create extra env
*/}}
{{- define "proxysql-cluster.extra-envs" }}
{
"MONITOR_PASSWORD": "{{ .Values.secret.monitor_password }}",
"CLUSTER_PASSWORD": "{{ .Values.secret.cluster_password }}"
}
{{- end }}

{{/*
Create the hummock option
*/}}
{{- define "proxysql-cluster.annotations.extra-envs" }}
"kubeblocks.io/extra-env": {{ include "proxysql-cluster.extra-envs" . | nospace  | quote }}
{{- end }}