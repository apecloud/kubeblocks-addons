{{/*
Expand the name of the chart.
*/}}
{{- define "yashandb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "yashandb.fullname" -}}
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
{{- define "yashandb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "yashandb.labels" -}}
helm.sh/chart: {{ include "yashandb.chart" . }}
{{ include "yashandb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "yashandb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "yashandb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common yashandb annotations
*/}}
{{- define "yashandb.annotations" -}}
helm.sh/resource-policy: keep
{{- end }}

{{/*
Define yashandb component definition name
*/}}
{{- define "yashandb.cmpdName" -}}
yashandb-{{ .Chart.Version }}
{{- end -}}

{{/*
Define yashandb component definition regular expression name prefix
*/}}
{{- define "yashandb.cmpdRegexpPattern" -}}
^yashandb-
{{- end -}}

{{/*
Define yashandb scripts template name
*/}}
{{- define "yashandb.scriptsTplName" -}}
yashandb-scripts-tpl
{{- end -}}

{{/*
Define yashandb config template name
*/}}
{{- define "yashandb.configTplName" -}}
yashandb-configuration-tpl
{{- end -}}

{{/*
Generate scripts configmap
*/}}
{{- define "yashandb.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}