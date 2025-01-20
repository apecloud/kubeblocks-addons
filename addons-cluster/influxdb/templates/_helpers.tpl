{{- define "influxdb-cluster.replicas" }}
{{- if eq .Values.mode "standalone" }}
{{- 1 }}
{{- else -}}
{{- .Values.replicas -}}
{{- end -}}
{{- end -}}