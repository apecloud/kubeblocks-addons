{{/*
Create extra env
*/}}
{{- define "minio-cluster.buckets" }}
{
"MINIO_BUCKETS": "{{ .Values.buckets | default "" }}",
}
{{- end }}

{{- define "minio-cluster.compdef" }}
  {{- include "minio-release.name" . }}
{{- end }}