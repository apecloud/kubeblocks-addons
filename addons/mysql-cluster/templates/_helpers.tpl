{{/*
Define replica count.
standalone mode: 1
replication mode: 2
raftGroup mode: 3 or more

orchestrator mode: 2 or more
*/}}
{{- define "mysql-cluster.replicaCount" -}}
{{- if eq .Values.haComponent.orchestrator.enable }}
replicas: {{ max .Values.replicas 2 }}
{{- else }}
    {{- if eq .Values.mode "standalone" }}
replicas: 1
    {{- else if eq .Values.mode "replication" }}
replicas: {{ max .Values.replicas 2 }}
    {{- else }}
replicas: {{ max .Values.replicas 3 }}
    {{- end }}
{{- end }}
{{- end }}