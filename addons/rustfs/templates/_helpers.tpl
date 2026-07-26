{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "rustfs.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "rustfs.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "rustfs.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "rustfs.labels" -}}
helm.sh/chart: {{ include "rustfs.chart" . }}
{{ include "rustfs.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "rustfs.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rustfs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "rustfs.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "rustfs.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "rustfs.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define rustfs component definition name
*/}}
{{- define "rustfs.cmpdName" -}}
rustfs-{{ .Chart.Version }}
{{- end -}}

{{/*
Define rustfs component definition regular expression name prefix
*/}}
{{- define "rustfs.cmpdRegexpPattern" -}}
^rustfs-
{{- end -}}

{{/*
Define rustfs script template name
*/}}
{{- define "rustfs.scriptTplName" -}}
rustfs-script-template
{{- end -}}

{{/*
Define rustfs config template name
*/}}
{{- define "rustfs.configTplName" -}}
rustfs-config-template
{{- end -}}

{{/*
Get RustFS default service version
*/}}
{{- define "rustfs.defaultServiceVersion" -}}
{{- $defaultVersion := "" -}}
{{- range .Values.versions -}}
  {{- if .isDefault -}}
    {{- $defaultVersion = .serviceVersion -}}
    {{- break -}}
  {{- end -}}
{{- end -}}
{{- if not $defaultVersion -}}
  {{- $defaultVersion = (index .Values.versions 0).serviceVersion -}}
{{- end -}}
{{- $defaultVersion -}}
{{- end -}}
