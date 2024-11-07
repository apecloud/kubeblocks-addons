{{/*
Expand the name of the chart.
*/}}
{{- define "nebula.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "nebula.fullname" -}}
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
Expand the namespace of the chart.
*/}}
{{- define "nebula.namespace" -}}
{{ .Release.Namespace }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nebula.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nebula.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nebula.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Nebula cluster labels
*/}}
{{- define "nebula.labels" -}}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "nebula.chart" . }}
{{ include "nebula.selectorLabels" . }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "nebula.annotations" -}}
helm.sh/resource-policy: keep
{{- end }}

{{/*
Define nebula metad component definition name
*/}}
{{- define "nebula-metad.cmpdName" -}}
nebula-metad-{{ .Chart.Version }}
{{- end -}}

{{/*
Define nebula metad component definition regex pattern
*/}}
{{- define "nebula-metad.cmpdRegexpPattern" -}}
^nebula-metad-
{{- end -}}

{{/*
Define nebula metad configuration template name
*/}}
{{- define "nebula-metad.configTemplateName" -}}
nebula-metad-config-template
{{- end -}}

{{/*
Define nebula graphd component definition name
*/}}
{{- define "nebula-graphd.cmpdName" -}}
nebula-graphd-{{ .Chart.Version }}
{{- end -}}

{{/*
Define nebula graphd component definition regex pattern
*/}}
{{- define "nebula-graphd.cmpdRegexpPattern" -}}
^nebula-graphd-
{{- end -}}

{{/*
Define nebula graphd configuration template name
*/}}
{{- define "nebula-graphd.configTemplateName" -}}
nebula-graphd-config-template
{{- end -}}

{{/*
Define nebula console component definition name
*/}}
{{- define "nebula-console.cmpdName" -}}
nebula-console-{{ .Chart.Version }}
{{- end -}}

{{/*
Define nebula console component definition regex pattern
*/}}
{{- define "nebula-console.cmpdRegexpPattern" -}}
^nebula-console-
{{- end -}}

{{/*
Define nebula storaged component definition name
*/}}
{{- define "nebula-storaged.cmpdName" -}}
nebula-storaged-{{ .Chart.Version }}
{{- end -}}

{{/*
Define nebula storaged component definition regex pattern
*/}}
{{- define "nebula-storaged.cmpdRegexpPattern" -}}
^nebula-storaged-
{{- end -}}

{{/*
Define nebula storaged configuration template name
*/}}
{{- define "nebula-storaged.configTemplateName" -}}
nebula-storaged-config-template
{{- end -}}

{{/*
Define nebula storaged scripts template name
*/}}
{{- define "nebula-storaged.scriptsTemplateName" -}}
nebula-storaged-scripts-template
{{- end -}}