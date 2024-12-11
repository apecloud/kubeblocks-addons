{{/*
Expand the name of the chart.
*/}}
{{- define "starrocks.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "starrocks.fullname" -}}
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
{{- define "starrocks.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "starrocks.labels" -}}
helm.sh/chart: {{ include "starrocks.chart" . }}
{{ include "starrocks.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "starrocks.selectorLabels" -}}
app.kubernetes.io/name: {{ include "starrocks.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "starrocks.annotations" -}}
helm.sh/resource-policy: keep
{{ include "starrocks.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "starrocks.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{- define "starrocks.fe.config" -}}
fe.conf: |
{{- if .Values.fe.config }}
{{ .Values.fe.config | indent 2 }}
{{- end }}
{{- end }}

{{- define "starrocks.be.config" -}}
be.conf: |
{{- if .Values.be.config }}
{{ .Values.be.config | indent 2 }}
{{- end }}
{{- end }}

{{- define "fe.componentDefName" -}}
starrocks-ce-fe-{{ .Chart.Version }}
{{- end -}}

{{- define "be.componentDefName" -}}
starrocks-ce-be-{{ .Chart.Version }}
{{- end -}}

{{/*
Define fe component definition regex pattern
*/}}
{{- define "fe.cmpdRegexPattern" -}}
^starrocks-ce-fe-
{{- end -}}

{{/*
Define be component definition regex pattern
*/}}
{{- define "be.cmpdRegexPattern" -}}
^starrocks-ce-fe-
{{- end -}}

{{/*
Define fe component configuration template name
*/}}
{{- define "fe.configurationTemplate" -}}
starrocks-ce-fe-configuration-template
{{- end -}}

{{/*
Define be component configuration template name
*/}}
{{- define "be.configurationTemplate" -}}
starrocks-ce-be-configuration-template
{{- end -}}

{{/*
Define starrocks scripts configMap template name
*/}}
{{- define "starrocks.scriptsTemplate" -}}
starrocks-ce-scripts-template
{{- end -}}