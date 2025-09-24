{{/*
Expand the name of the chart.
*/}}
{{- define "doris.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "doris.fullname" -}}
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
{{- define "doris.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "doris.labels" -}}
helm.sh/chart: {{ include "doris.chart" . }}
{{ include "doris.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "doris.selectorLabels" -}}
app.kubernetes.io/name: {{ include "doris.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "doris.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "doris.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "doris.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{- define "doris.fe.config" -}}
fe.conf: |
{{- if .Values.fe.config }}
{{ .Values.fe.config | indent 2 }}
{{- end }}
{{- end }}

{{- define "doris.be.config" -}}
be.conf: |
{{- if .Values.be.config }}
{{ .Values.be.config | indent 2 }}
{{- end }}
{{- end }}

{{- define "fe.componentDefName" -}}
doris-fe-{{ .Chart.Version }}
{{- end -}}

{{- define "be.componentDefName" -}}
doris-be-{{ .Chart.Version }}
{{- end -}}


{{- define "fe.componentVersionName" -}}
doris-fe
{{- end -}}

{{- define "be.componentVersionName" -}}
doris-be
{{- end -}}

{{/*
Define fe component definition regex pattern
*/}}
{{- define "fe.cmpdRegexPattern" -}}
^doris-fe-
{{- end -}}

{{/*
Define be component definition regex pattern
*/}}
{{- define "be.cmpdRegexPattern" -}}
^doris-be-
{{- end -}}

{{/*
Define fe component configuration template name
*/}}
{{- define "fe.configurationTemplate" -}}
doris-fe-configuration-template
{{- end -}}

{{/*
Define be component configuration template name
*/}}
{{- define "be.configurationTemplate" -}}
doris-be-configuration-template
{{- end -}}

{{/*
Define doris fe component scripts configMap template name
*/}}
{{- define "fe.scriptsTemplate" -}}
doris-fe-scripts-template
{{- end -}}

{{/*
Define doris be component scripts configMap template name
*/}}
{{- define "be.scriptsTemplate" -}}
doris-be-scripts-template
{{- end -}}