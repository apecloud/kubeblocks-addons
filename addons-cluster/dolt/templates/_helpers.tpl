{{/*
ComponentDefinition from mode (must match addons/dolt: dolt-replication | dolt-standalone).
*/}}
{{- define "dolt-cluster.componentDef" -}}
{{- if eq .Values.mode "standalone" -}}
dolt-standalone
{{- else -}}
dolt-replication
{{- end -}}
{{- end }}

{{/*
Replica count: standalone is always 1; otherwise use .Values.replicas.
*/}}
{{- define "dolt-cluster.replicas" -}}
{{- if eq .Values.mode "standalone" -}}
1
{{- else -}}
{{ .Values.replicas }}
{{- end -}}
{{- end }}
