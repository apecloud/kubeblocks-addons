{{/*
Define replica count.
*/}}
{{- define "camellia-redis-proxy.replicaCount" }}
replicas: {{ .Values.replicas | default 2 }}
{{- end }}
