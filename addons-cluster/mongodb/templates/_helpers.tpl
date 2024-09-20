{{/*
Define replica count.
standalone topology: 1
replicaset topology: 3
*/}}

{{- define "mongodb-cluster.replicaCount" }}
{{- if eq .Values.topology "standalone" }}
replicas: 1
{{- else if eq .Values.topology "replicaset" }}
replicas: {{ max .Values.replicas 3 }}
{{- end }}
{{- end }}
