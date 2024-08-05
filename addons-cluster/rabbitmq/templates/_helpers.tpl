{{/*
Define replica count.
standalone mode: 1
replicaset mode: 3
*/}}

{{- define "rabbitmq-cluster.replicaCount" }}
{{- if eq .Values.mode "singlenode" }}
replicas: 1
{{- else if eq .Values.mode "clustermode" }}
replicas: {{ max .Values.replicas 3 }}
{{- end }}
{{- end }}
