{{/*
Define replica count.
standalone topology: 1
replication topology: 2
*/}}
{{- define "opengauss-cluster.replicaCount" }}
{{- if eq .Values.topology "standalone" }}
replicas: 1
{{- else if eq .Values.topology "replication" }}
replicas: {{ max .Values.replicas 2 }}
{{- end }}
{{- end }}