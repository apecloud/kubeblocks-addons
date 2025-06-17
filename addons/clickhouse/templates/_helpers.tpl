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
Extract major version from AppVersion (e.g., "25.4.4" -> "25")
*/}}
{{- define "clickhouse.majorVersion" -}}
{{- .Chart.AppVersion | regexFind "^[0-9]+" }}
{{- end }}

{{/*
=== CLICKHOUSE COMPONENT DEFINITIONS ===
*/}}

{{/*
Define clickhouse component definition name
*/}}
{{- define "clickhouse.cmpdName" -}}
clickhouse-{{ include "clickhouse.majorVersion" . }}-{{ .Chart.Version }}
{{- end }}

{{/*
Define clickhouse component definition regex pattern
*/}}
{{- define "clickhouse.cmpdRegexpPattern" -}}
^clickhouse-{{ include "clickhouse.majorVersion" . }}.*
{{- end }}

{{/*
=== CLICKHOUSE-KEEPER COMPONENT DEFINITIONS ===
*/}}

{{/*
Define clickhouse-keeper component definition name
*/}}
{{- define "clickhouse-keeper.cmpdName" -}}
clickhouse-keeper-{{ include "clickhouse.majorVersion" . }}-{{ .Chart.Version }}
{{- end }}

{{/*
Define clickhouse-keeper component definition regex pattern
*/}}
{{- define "clickhouse-keeper.cmpdRegexpPattern" -}}
^clickhouse-keeper-{{ include "clickhouse.majorVersion" . }}.*
{{- end }}

{{/*
=== PARAMETER DEFINITIONS ===
*/}}

{{/*
Define clickhouse config parameter definition name
*/}}
{{- define "clickhouse.paramsDefName" -}}
clickhouse-{{ include "clickhouse.majorVersion" . }}-pd
{{- end }}

{{/*
Define clickhouse user parameter definition name
*/}}
{{- define "clickhouse.userParamsDefinition" -}}
clickhouse-{{ include "clickhouse.majorVersion" . }}-user-pd
{{- end }}

{{/*
Define clickhouse config parameter definition name
*/}}
{{- define "clickhouse.configParamsDefinition" -}}
clickhouse-{{ include "clickhouse.majorVersion" . }}-config-pd
{{- end }}

{{/*
Define clickhouse keeper parameter definition name
*/}}
{{- define "clickhouse.keeperParamsDefinition" -}}
clickhouse-{{ include "clickhouse.majorVersion" . }}-keeper-pd
{{- end }}

{{/*
=== PARAMETER CONFIGURATION RULES ===
*/}}

{{/*
Define clickhouse keeper PCR with chart version
*/}}
{{- define "clickhouse.keeperPcr" -}}
clickhouse-{{ include "clickhouse.majorVersion" . }}-keeper-pcr-{{ .Chart.Version }}
{{- end }}

{{/*
Define clickhouse PCR with chart version
*/}}
{{- define "clickhouse.pcr" -}}
clickhouse-{{ include "clickhouse.majorVersion" . }}-pcr-{{ .Chart.Version }}
{{- end }}

{{/*
=== CONFIGURATION TEMPLATES ===
*/}}

{{/*
Define clickhouse default overrides configuration template name
*/}}
{{- define "clickhouse.configurationTplName" -}}
clickhouse-{{ include "clickhouse.majorVersion" . }}-configuration-tpl
{{- end }}

{{/*
Define clickhouse client configuration template name
*/}}
{{- define "clickhouse.clientTplName" -}}
clickhouse-{{ include "clickhouse.majorVersion" . }}-client-configuration-tpl
{{- end }}

{{/*
Define clickhouse user configuration template name
*/}}
{{- define "clickhouse.userTplName" -}}
clickhouse-{{ include "clickhouse.majorVersion" . }}-user-configuration-tpl
{{- end }}

{{/*
Define clickhouse-keeper configuration template name
*/}}
{{- define "clickhouse-keeper.configurationTplName" -}}
clickhouse-keeper-{{ include "clickhouse.majorVersion" . }}-configuration-tpl
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

{{/*
Define clickhouse image based on current major version
*/}}
{{- define "clickhouse.image" -}}
{{- $majorVersion := include "clickhouse.majorVersion" . }}
{{- if eq $majorVersion "22" }}
{{ include "clickhouse.repository" . }}:{{ .Values.image.tag.major22 }}
{{- else if eq $majorVersion "24" }}
{{ include "clickhouse.repository" . }}:{{ .Values.image.tag.major24 }}
{{- else if eq $majorVersion "25" }}
{{ include "clickhouse.repository" . }}:{{ .Values.image.tag.major25 }}
{{- else }}
{{ include "clickhouse.repository" . }}:{{ .Values.image.tag.major25 }}
{{- end }}
{{- end }}

{{/*
Define clickhouse22 image
*/}}
{{- define "clickhouse22.image" -}}
{{ include "clickhouse.repository" . }}:{{ .Values.image.tag.major22 }}
{{- end }}

{{/*
Define clickhouse24 image
*/}}
{{- define "clickhouse24.image" -}}
{{ include "clickhouse.repository" . }}:{{ .Values.image.tag.major24 }}
{{- end }}

{{/*
Define clickhouse25 image
*/}}
{{- define "clickhouse25.image" -}}
{{ include "clickhouse.repository" . }}:{{ .Values.image.tag.major25 }}
{{- end }}
