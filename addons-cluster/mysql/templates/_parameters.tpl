{{/*
Define parameters template.
*/}}
{{- define "parameters.customTemplate" -}}
{{- if .Values.parameterTemplate }}
{{- if and ( not ( empty ( index .Values.parameterTemplate "templateRef" | default "" | trim ) ) ) ( not ( empty ( index .Values.parameterTemplate "namespace" | default "" | trim ) ) ) }}
{{- $customTemplate := dict "mysql-replication-config" .Values.parameterTemplate }}
annotations:
  "config.kubeblocks.io/custom-template": {{ $customTemplate | toJson | quote }}
{{- end }}
{{- end }}
{{- end }}