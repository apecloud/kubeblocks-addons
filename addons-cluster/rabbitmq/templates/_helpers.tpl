{{/*
Define replica count.
standalone topology: 1
replicaset topology: 3
*/}}

{{- define "rabbitmq-cluster.replicaCount" }}
{{- if eq .Values.topology "singlenode" }}
replicas: 1
{{- else if eq .Values.topology "clustermode" }}
replicas: {{ max .Values.replicas 3 }}
{{- end }}
{{- end }}
