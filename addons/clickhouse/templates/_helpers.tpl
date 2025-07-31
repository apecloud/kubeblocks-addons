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
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "clickhouse.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "clickhouse.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}


{{/*
=== CLICKHOUSE COMPONENT DEFINITIONS ===
*/}}

{{/*
Define clickhouse component definition name
*/}}
{{- define "clickhouse.cmpdName" -}}
clickhouse-{{ .Chart.Version }}
{{- end }}

{{/*
Define clickhouse component definition regex pattern
*/}}
{{- define "clickhouse.cmpdRegexpPattern" -}}
^clickhouse-1.*
{{- end }}

{{/*
=== CLICKHOUSE-KEEPER COMPONENT DEFINITIONS ===
*/}}

{{/*
Define clickhouse-keeper component definition name
*/}}
{{- define "clickhouse-keeper.cmpdName" -}}
clickhouse-keeper-{{ .Chart.Version }}
{{- end }}

{{/*
Define clickhouse-keeper component definition regex pattern
*/}}
{{- define "clickhouse-keeper.cmpdRegexpPattern" -}}
^clickhouse-keeper-1.*
{{- end }}

{{/*
=== PARAMETER DEFINITIONS ===
*/}}

{{/*
Define clickhouse config parameter definition name
*/}}
{{- define "clickhouse.paramsDefName" -}}
clickhouse-pd
{{- end }}

{{/*
Define clickhouse user parameter definition name
*/}}
{{- define "clickhouse.userParamsDefinition" -}}
clickhouse-user-pd
{{- end }}

{{/*
Define clickhouse config parameter definition name
*/}}
{{- define "clickhouse.configParamsDefinition" -}}
clickhouse-config-pd
{{- end }}

{{/*
Define clickhouse keeper parameter definition name
*/}}
{{- define "clickhouse.keeperParamsDefinition" -}}
clickhouse-keeper-pd
{{- end }}

{{/*
=== PARAMETER CONFIGURATION RULES ===
*/}}

{{/*
Define clickhouse keeper PCR with chart version
*/}}
{{- define "clickhouse.keeperPcr" -}}
clickhouse-keeper-pcr-{{ .Chart.Version }}
{{- end }}

{{/*
Define clickhouse PCR with chart version
*/}}
{{- define "clickhouse.pcr" -}}
clickhouse-pcr-{{ .Chart.Version }}
{{- end }}

{{/*
=== CONFIGURATION TEMPLATES ===
*/}}

{{/*
Define clickhouse default overrides configuration template name
*/}}
{{- define "clickhouse.configurationTplName" -}}
clickhouse-configuration-tpl
{{- end }}

{{/*
Define clickhouse client configuration template name
*/}}
{{- define "clickhouse.clientTplName" -}}
clickhouse-client-configuration-tpl
{{- end }}

{{/*
Define clickhouse user configuration template name
*/}}
{{- define "clickhouse.userTplName" -}}
clickhouse-user-configuration-tpl
{{- end }}

{{/*
Define clickhouse-keeper configuration template name
*/}}
{{- define "clickhouse-keeper.configurationTplName" -}}
clickhouse-keeper-configuration-tpl
{{- end }}

{{/*
=== IMAGE DEFINITIONS ===
*/}}

{{/*
Define clickhouse image repository
*/}}

{{/*
Define busybox image
*/}}
{{- define "busybox.image" -}}
{{ .Values.busyboxImage.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.busyboxImage.repository}}:{{ .Values.busyboxImage.tag }}
{{- end }}

{{- define "clickhouse.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}
