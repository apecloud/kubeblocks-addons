{{/*
Define replica count.
standalone topology: 1
raftGroup topology: 3 or more
*/}}
{{- define "tdengine-cluster.replicaCount" -}}
{{- if eq .Values.topology "standalone" }}
replicas: 1
{{- else }}
replicas: {{ max .Values.replicas 3 }}
{{- end }}
{{- end -}}