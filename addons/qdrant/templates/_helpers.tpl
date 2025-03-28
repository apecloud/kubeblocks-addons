{{/*
Expand the name of the chart.
*/}}
{{- define "qdrant.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "qdrant.fullname" -}}
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
{{- define "qdrant.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "qdrant.labels" -}}
helm.sh/chart: {{ include "qdrant.chart" . }}
{{ include "qdrant.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "qdrant.selectorLabels" -}}
app.kubernetes.io/name: {{ include "qdrant.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "qdrant.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "qdrant.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "qdrant.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define qdrant component definition name
*/}}
{{- define "qdrant.cmpdName" -}}
qdrant-{{ .Chart.Version }}
{{- end -}}

{{/*
Define qdrant component definition regex pattern
*/}}
{{- define "qdrant.cmpdRegexPattern" -}}
^qdrant-
{{- end -}}

{{/*
Define qdrant scripts tpl name
*/}}
{{- define "qdrant.scriptsTplName" -}}
qdrant-scripts-template
{{- end -}}

{{/*
Define qdrant configuration tpl name
*/}}
{{- define "qdrant.configTplName" -}}
qdrant-config-template
{{- end -}}

{{/*
Define qdrant config constraint name
*/}}
{{- define "qdrant.configConstraintName" -}}
qdrant-config-constraints
{{- end -}}

{{/*
Define qdrant parameter config renderer name
*/}}
{{- define "qdrant.pcrName" -}}
qdrant-pcr
{{- end -}}
