{{/*
Expand the name of the chart.
*/}}
{{- define "tdengine.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "tdengine.fullname" -}}
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
{{- define "tdengine.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tdengine.labels" -}}
helm.sh/chart: {{ include "tdengine.chart" . }}
{{ include "tdengine.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tdengine.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tdengine.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "tdengine.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "tdengine.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "tdengine.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define tdengine component definition name
*/}}
{{- define "tdengine.cmpdName" -}}
tdengine-{{ .Chart.Version }}
{{- end -}}

{{/*
Define tdengine component version name
*/}}
{{- define "tdengine.cmpvName" -}}
tdengine
{{- end -}}

{{/*
Define tdengine component definition regex pattern
*/}}
{{- define "tdengine.cmpdRegexPattern" -}}
^tdengine-
{{- end -}}

{{/*
Define tdengine config template name
*/}}
{{- define "tdengine.configTemplate" -}}
tdengine-config-template
{{- end -}}

{{/*
Define tdengine script template name
*/}}
{{- define "tdengine.scriptTemplate" -}}
tdengine-script-template
{{- end -}}

{{/*
Define tdengine metrice config template name
*/}}
{{- define "tdengine.metricsConfigTemplate" -}}
tdengine-metrics-config-template
{{- end -}}
