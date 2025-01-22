{{/*
Define replica count.
semisync: 2 or more
mgr: 3 or more
orchestrator mode: 2 or more
*/}}
{{- define "mysql-cluster.replicaCount" -}}
{{- if .Values.orchestrator.enable }}
replicas: {{ max .Values.replicas 2 }}
{{- else }}
    {{- if hasPrefix "semisync" .Values.topology }}
replicas: 2
    {{- else if hasPrefix "mgr" .Values.topology }}
replicas: {{ max .Values.replicas 3 }}
    {{- else }}
replicas: {{ max .Values.replicas 2 }}
    {{- end }}
{{- end }}
{{- end }}