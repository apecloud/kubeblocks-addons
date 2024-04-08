{{- define "orchestrator.replicaCount" -}}
replicas: {{  .Values.replicas.orchestrator  }}
{{- end -}}
