{{/*
Define the cluster name.
We truncate at 15 chars because KubeBlocks will concatenate the names of other resources with cluster name
*/}}
{{- define "dmdb-cluster.name" }}
{{- $name := .Release.Name }}
{{- if not (regexMatch "^[a-z]([-a-z0-9]*[a-z0-9])?$" $name) }}
{{ fail (printf "Release name %q is invalid. It must match the regex %q." $name "^[a-z]([-a-z0-9]*[a-z0-9])?$") }}
{{- end }}
{{- if gt (len $name) 16 }}
{{ fail (printf "Release name %q is invalid, must be no more than 15 characters" $name) }}
{{- end }}
{{- $name }}
{{- end }}

{{/*
Define cluster labels
*/}}
{{- define "dmdb-cluster.labels" -}}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/name: {{ .Chart.Name | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/instance: {{ include "dmdb-cluster.name" . }}
{{- end }}
