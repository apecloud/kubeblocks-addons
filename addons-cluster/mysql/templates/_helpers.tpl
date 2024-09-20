{{/*
Define replica count.
standalone topology: 1
replication topology: 2
raftGroup topology: 3 or more

orchestrator topology: 2 or more
*/}}
{{- define "mysql-cluster.replicaCount" -}}
{{- if .Values.orchestrator.enable }}
replicas: {{ max .Values.replicas 2 }}
{{- else }}
    {{- if eq .Values.topology "standalone" }}
replicas: 1
    {{- else if eq .Values.topology "replication" }}
replicas: {{ max .Values.replicas 2 }}
    {{- else }}
replicas: {{ max .Values.replicas 3 }}
    {{- end }}
{{- end }}
{{- end }}