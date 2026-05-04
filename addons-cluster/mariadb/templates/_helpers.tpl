{{- define "mariadb-cluster.replicas" }}
{{- if eq .Values.topology "standalone" }}
{{- 1 }}
{{- else -}}
{{- .Values.replicas -}}
{{- end -}}
{{- end -}}
