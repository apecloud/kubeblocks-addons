{{- define "mariadb-cluster.replicas" }}
{{- if eq .Values.topology "standalone" }}
{{- 1 }}
{{- end -}}
{{- end -}}