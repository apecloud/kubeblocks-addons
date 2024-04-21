{{/*
Define monitor
*/}}
{{- define "kblib.componentMonitor" }}
{{- if int .Values.extra.monitorEnabled }}
monitorEnabled: true
{{- with .Values.sidecars }}
sidecars:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- else }}
monitorEnabled: false
{{- end }}
{{- end }}