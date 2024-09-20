{{/*
Define replicas.
standalone mode: 1
raftGroup mode: max(replicas, 3)
*/}}
{{- define "apecloud-postgresql-cluster.replicas" }}
{{- if eq .Values.topology "standalone" }}
{{- 1 }}
{{- else if eq .Values.topology "raftGroup" }}
{{- max .Values.replicas 3 }}
{{- end }}
{{- end -}}