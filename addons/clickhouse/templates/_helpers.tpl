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
Define clickhouse component definition name
*/}}
{{- define "clickhouse.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.clickhouse ) 0 -}}
clickhouse-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.clickhouse -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define clickhouse component definition regex pattern
*/}}
{{- define "clickhouse.cmpdRegexpPattern" -}}
^clickhouse-.*
{{- end -}}

{{/*
Define clickhouse-keeper component definition name
*/}}
{{- define "clickhouse-keeper.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.keeper ) 0 -}}
clickhouse-keeper-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.keeper -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define clickhouse-keeper component definition regex pattern
*/}}
{{- define "clickhouse-keeper.cmpdRegexpPattern" -}}
^clickhouse-keeper-.*
{{- end -}}

{{/*
Define clickhouse config constraint name
*/}}
{{- define "clickhouse.configConstraintName" -}}
clickhouse-config-constraints
{{- end -}}

{{/*
Define clickhouse default overrides configuration tpl name
*/}}
{{- define "clickhouse.configurationTplName" -}}
clickhouse-configuration-tpl
{{- end -}}

{{/*
Define clickhouse client configuration tpl name
*/}}
{{- define "clickhouse.clientTplName" -}}
clickhouse-client-configuration-tpl
{{- end -}}

{{/*
Define clickhouse user configuration tpl name
*/}}
{{- define "clickhouse.userTplName" -}}
clickhouse-user-configuration-tpl
{{- end -}}

{{/*
Define clickhouse-keeper configuration tpl name
*/}}
{{- define "clickhouse-keeper.configurationTplName" -}}
clickhouse-keeper-configuration-tpl
{{- end -}}

{{/*
Define clickhouse image repository
*/}}
{{- define "clickhouse.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}
