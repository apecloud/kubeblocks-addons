{{/*
Expand the name of the chart.
*/}}
{{- define "victoria-metrics.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "victoria-metrics.fullname" -}}
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
{{- define "victoria-metrics.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "victoria-metrics.labels" -}}
helm.sh/chart: {{ include "victoria-metrics.chart" . }}
{{ include "victoria-metrics.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "victoria-metrics.selectorLabels" -}}
app.kubernetes.io/name: {{ include "victoria-metrics.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "victoria-metrics.annotations" -}}
helm.sh/resource-policy: keep
{{- end }}

{{/*
Define component definition name
*/}}
{{- define "vmstorage.componentDefName" -}}
vmstorage-{{ .Chart.Version }}
{{- end -}}

{{/*
Define victoria-metrics stroage component definition regular expression name prefix
*/}}
{{- define "vmstorage.cmpdRegexpPattern" -}}
^vmstorage-
{{- end -}}

{{/*
Define component definition name
*/}}
{{- define "vminsert.componentDefName" -}}
vminsert-{{ .Chart.Version }}
{{- end -}}

{{/*
Define victoria-metrics insert component definition regular expression name prefix
*/}}
{{- define "vminsert.cmpdRegexpPattern" -}}
^vminsert-
{{- end -}}

{{/*
Define component definition name
*/}}
{{- define "vmselect.componentDefName" -}}
vmselect-{{ .Chart.Version }}
{{- end -}}

{{/*
Define victoria-metrics select component definition regular expression name prefix
*/}}
{{- define "vmselect.cmpdRegexpPattern" -}}
^vmselect-
{{- end -}}

{{/*
Define victoria-metrics config name
*/}}
{{- define "victoria-metrics.configName" -}}
{{ include "victoria-metrics.name" . }}-config
{{- end -}}