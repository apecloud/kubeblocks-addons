{{/*
Expand the name of the chart.
*/}}
{{- define "mogdb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mogdb.fullname" -}}
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
{{- define "mogdb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mogdb.labels" -}}
helm.sh/chart: {{ include "mogdb.chart" . }}
{{ include "mogdb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mogdb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mogdb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common mogdb annotations
*/}}
{{- define "mogdb.annotations" -}}
helm.sh/resource-policy: keep
{{- end }}

{{/*
Define mogdb component definition name
*/}}
{{- define "mogdb.cmpdName" -}}
mogdb-{{ .Chart.Version }}
{{- end -}}

{{/*
Define mogdb component definition regular expression name prefix
*/}}
{{- define "mogdb.cmpdRegexpPattern" -}}
^mogdb-
{{- end -}}

{{/*
Define mogdb scripts template name
*/}}
{{- define "mogdb.scriptsTplName" -}}
mogdb-scripts-tpl
{{- end -}}

{{/*
Define mogdb config template name
*/}}
{{- define "mogdb.configTplName" -}}
mogdb-configuration-tpl
{{- end -}}

{{/*
Define mogdb config constraint name
*/}}
{{- define "mogdb.constraintTplName" -}}
mogdb-cc
{{- end -}}

{{/*
Generate scripts configmap
*/}}
{{- define "mogdb.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}
