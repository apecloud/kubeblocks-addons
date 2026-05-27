{{/*
Build the OpenViking client-facing Service block.
*/}}
{{- define "openviking-cluster.service" -}}
{{- if .Values.service.type }}
services:
  - name: http
    serviceName: openviking-http
    {{- if and (eq .Values.service.type "LoadBalancer") (not (empty .Values.service.annotations)) }}
    annotations: {{ .Values.service.annotations | toYaml | nindent 8 }}
    {{- end }}
    spec:
      type: {{ .Values.service.type }}
      ports:
        - port: {{ .Values.service.port }}
          targetPort: 1933
          {{- if .Values.service.nodePort }}
          nodePort: {{ .Values.service.nodePort }}
          {{- end }}
    componentSelector: openviking
{{- end }}
{{- end }}
