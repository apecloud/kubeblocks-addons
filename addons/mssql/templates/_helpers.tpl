{{- /*
Copyright ApeCloud Co., Ltd. All Rights Reserved.
SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "mssql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mssql.fullname" -}}
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
{{- define "mssql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mssql.labels" -}}
helm.sh/chart: {{ include "mssql.chart" . }}
{{ include "mssql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "mssql.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "mssql.apiVersion" . }}
{{- end }}

{{/*
Regex pattern matching all MSSQL ComponentDefinitions across all major versions.
Used in ClusterDefinition compDef fields and componentVarRef.compDef.
*/}}
{{- define "mssql.cmpdRegexpPattern" -}}
^mssql-\d+
{{- end }}

{{/*
API version annotation
*/}}
{{- define "mssql.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mssql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mssql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "mssql.sysConfigurationsConfigMapName" -}}
{{- $major := .major -}}
{{- $root := .root -}}
mssql{{ .major }}-sys-configurations-config-{{ $.root.Chart.Version }}
{{- end -}}

{{- define "mssql.sysConfigurationsParamsDefName" -}}
{{- $major := .major -}}
{{- $root := .root -}}
mssql{{ $major }}-sys-configurations-pd-{{ $root.Chart.Version }}
{{- end -}}

{{- define "mssql.configMapName" -}}
{{- $major := .major -}}
{{- $root := .root -}}
mssql{{ $major }}-config-{{ $root.Chart.Version }}
{{- end -}}

{{- define "mssql.paramsDefName" -}}
{{- $major := .major -}}
{{- $root := .root -}}
mssql{{ $major }}-pd-{{ $root.Chart.Version }}
{{- end -}}

{{- define "mssql.pcr" -}}
{{- $major := .major -}}
{{- $root := .root -}}
mssql{{ $major }}-pcr-{{ $root.Chart.Version }}
{{- end -}}

{{- define "mssql.scriptsTemplate" -}}
mssql-scripts-{{ .Chart.Version }}
{{- end -}}

{{/*
Get mssql image address by major and minor version
Parameters: major (string), minor (string), root context
Usage: {{ include "mssql.imageByVersion" (dict "major" "2022" "minor" "2022-CU19" "root" .) }}
*/}}
{{- define "mssql.imageByVersion" -}}
{{- $major := .major -}}
{{- $minor := .minor -}}
{{- $root := .root -}}
{{- $tag := "" -}}
{{- range $root.Values.versions -}}
  {{- if eq .major $major -}}
    {{- range .minors -}}
      {{- if eq .version $minor -}}
        {{- $tag = .tag -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if $tag -}}
{{- printf "%s/%s:%s" ($root.Values.image.registry | default "docker.io") $root.Values.image.repository $tag -}}
{{- else -}}
{{- printf "%s/%s:latest" ($root.Values.image.registry | default "docker.io") $root.Values.image.repository -}}
{{- end -}}
{{- end -}}

{{/*
Get MSSQL componentDef by major version
Parameters: major (string), root context
Usage: {{ include "mssql.componentDefByMajor" (dict "major" "2022" "root" .) }}
*/}}
{{- define "mssql.componentDefByMajor" -}}
{{- $major := .major -}}
{{- $root := .root -}}
{{- $componentDef := "" -}}
{{- range $root.Values.versions -}}
  {{- if eq .major $major -}}
    {{- $componentDef = .componentDef -}}
    {{- break -}}
  {{- end -}}
{{- end -}}
{{- if $componentDef -}}
{{- printf "%s-%s" $componentDef $root.Chart.Version -}}
{{- else -}}
{{- fail (printf "componentDef not found for major: %s" $major) -}}
{{- end -}}
{{- end -}}
