{{/*
Define replica count.
standalone or standby mode: 1
replication mode: 2
*/}}
{{- define "postgresql-cluster.replicaCount" }}
{{- if or (eq .Values.mode "standalone") .Values.remoteSetting.isStandby }}
replicas: 1
{{- else if eq .Values.mode "replication" }}
replicas: {{ max .Values.replicas 2 }}
{{- end }}
{{- end }}