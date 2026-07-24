{{/*
Expand the name of the chart.
*/}}
{{- define "yashandb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "yashandb.fullname" -}}
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
{{- define "yashandb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "yashandb.labels" -}}
helm.sh/chart: {{ include "yashandb.chart" . }}
{{ include "yashandb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "yashandb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "yashandb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common yashandb annotations
*/}}
{{- define "yashandb.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "yashandb.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "yashandb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define yashandb component definition name
*/}}
{{- define "yashandb.cmpdName" -}}
yashandb-{{ .Chart.Version }}
{{- end -}}

{{/*
Define yashandb component definition regular expression name prefix
*/}}
{{- define "yashandb.cmpdRegexpPattern" -}}
^yashandb-
{{- end -}}

{{/*
Define yashandb scripts template name
*/}}
{{- define "yashandb.scriptsTplName" -}}
{{- printf "yashandb-scripts-tpl-%s" .Chart.Version | replace "." "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Define yashandb config template name
*/}}
{{- define "yashandb.configTplName" -}}
{{- printf "yashandb-configuration-tpl-%s" .Chart.Version | replace "." "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
2026-07-06 Reason: ParametersDefinition must reference the ComponentDefinition config entry, not the generated ConfigurationTemplate name.
Purpose: keep config and parameter binding names drift-free across templates.
Time: 2026-07-06.
*/}}
{{- define "yashandb.configEntryName" -}}
yashandb-configs
{{- end -}}

{{/*
Define yashandb parameters definition name
*/}}
{{- define "yashandb.paramsDefName" -}}
yashandb-configuration-pd
{{- end -}}

{{/*
Define YashanDB exporter source config map name.
*/}}
{{- define "yashandb.metricsConfigName" -}}
{{- printf "yashandb-exporter-config-%s" .Chart.Version | replace "." "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Define the optional YashanDB exporter image.
*/}}
{{- define "yashandb.metricsImage" -}}
{{ .Values.metrics.image.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.metrics.image.repository }}:{{ .Values.metrics.image.tag }}
{{- end -}}

{{/*
Define the local YashanDB port scraped by the optional exporter sidecar.
*/}}
{{- define "yashandb.metricsTargetPort" -}}
{{- if .Values.metrics.target.port -}}
{{ .Values.metrics.target.port }}
{{- else if .Values.ha.fixedAddress.enabled -}}
{{ .Values.ha.fixedAddress.dbPort | default 2688 }}
{{- else -}}
1688
{{- end -}}
{{- end -}}

{{/*
Generate scripts configmap
*/}}
{{- define "yashandb.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}


