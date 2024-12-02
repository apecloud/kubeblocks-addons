{{/*
Expand the name of the chart.
*/}}
{{- define "clickhouse.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "clickhouse.fullname" -}}
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
{{- define "clickhouse.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "clickhouse.labels" -}}
helm.sh/chart: {{ include "clickhouse.chart" . }}
{{ include "clickhouse.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "clickhouse.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clickhouse.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "clickhouse.annotations" -}}
helm.sh/resource-policy: keep
{{ include "clickhouse.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "clickhouse.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define clickhouse 24.X component definition name
*/}}
{{- define "clickhouse24.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.clickhouse24 ) 0 -}}
clickhouse-24-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.clickhouse24 -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define clickhouse24 component definition regex pattern
*/}}
{{- define "clickhouse24.cmpdRegexpPattern" -}}
^clickhouse-24.*
{{- end -}}

{{/*
Define clickhouse-keeper24 component definition name
*/}}
{{- define "clickhouse-keeper24.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.keeper24 ) 0 -}}
clickhouse-keeper-24-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.keeper24 -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define clickhouse-keeper24 component definition regex pattern
*/}}
{{- define "clickhouse-keeper24.cmpdRegexpPattern" -}}
^clickhouse-keeper-24.*
{{- end -}}

{{/*
Define clickhouse24 config constraint name
*/}}
{{- define "clickhouse24.configConstraintName" -}}
clickhouse-24-config-constraints
{{- end -}}

{{/*
Define clickhouse24 default overrides configuration tpl name
*/}}
{{- define "clickhouse24.configurationTplName" -}}
clickhouse-24-configuration-tpl
{{- end -}}

{{/*
Define clickhouse24 client configuration tpl name
*/}}
{{- define "clickhouse24.clientTplName" -}}
clickhouse-24-client-configuration-tpl
{{- end -}}

{{/*
Define clickhouse24 user configuration tpl name
*/}}
{{- define "clickhouse24.userTplName" -}}
clickhouse-24-user-configuration-tpl
{{- end -}}

{{/*
Define clickhouse-keeper24 configuration tpl name
*/}}
{{- define "clickhouse-keeper24.configurationTplName" -}}
clickhouse-keeper-24-configuration-tpl
{{- end -}}

{{/*
Define clickhouse image repository
*/}}
{{- define "clickhouse.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{/*
Define clickhouse24 image
*/}}
{{- define "clickhouse24.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}
