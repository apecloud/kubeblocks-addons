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

{{- define "rabbitmq-cluster.tls" }}
tls: {{ .Values.tls.enabled }}
{{- if .Values.tls.enabled }}
issuer:
  name: {{ .Values.tls.issuer }}
{{- if eq .Values.tls.issuer "UserProvided" }}
  secretRef:
    name: {{ .Values.tls.secretName | default (printf "%s-tls" (include "kblib.clusterName" .)) }}
    namespace: {{ .Release.Namespace }}
    ca: ca.crt
    cert: tls.crt
    key: tls.key
{{- end }}
{{- end }}
{{- end }}
