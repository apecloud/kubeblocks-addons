{{/*
Define replica count.
standalone mode: 1
replication mode: 2
*/}}
{{- define "official-postgresql-cluster.replicaCount" }}
{{- if eq .Values.topology "standalone" }}
replicas: 1
{{- else if eq .Values.topology "replication" }}
replicas: {{ max .Values.replicas 2 }}
{{- end }}
{{- end }}