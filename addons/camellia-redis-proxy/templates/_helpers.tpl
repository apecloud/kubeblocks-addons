{{/*
Expand the name of the chart.
*/}}
{{- define "camellia-redis-proxy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Define redis component defintion name
*/}}
{{- define "camellia-redis-proxy.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
camellia-redis-proxy
{{- else -}}
{{- printf "camellia-redis-proxy-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "camellia-redis-proxy.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "camellia-redis-proxy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "camellia-redis-proxy.labels" -}}
helm.sh/chart: {{ include "camellia-redis-proxy.chart" . }}
{{ include "camellia-redis-proxy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "camellia-redis-proxy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "camellia-redis-proxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Define image
*/}}
{{- define "camellia-redis-proxy.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}

{{- define "busybox.image" -}}
{{ .Values.busyboxImage.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.busyboxImage.repository}}:{{ .Values.busyboxImage.tag }}
{{- end }}}


{{/*
Generate scripts configmap
*/}}
{{- define "camellia-redis-proxy.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}