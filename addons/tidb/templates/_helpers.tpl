{{/*
Expand the name of the chart.
*/}}
{{- define "tidb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "tidb.fullname" -}}
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
{{- define "tidb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tidb.labels" -}}
helm.sh/chart: {{ include "tidb.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "tidb.cmScriptsName" -}}
tidb-scripts
{{- end -}}

{{- define "tidb.tidb.configTplName" -}}
tidb-config-template
{{- end -}}

{{- define "tidb.tikv.configTplName" -}}
tikv-config-template
{{- end -}}

{{- define "tidb.pd.configTplName" -}}
tidb-pd-config-template
{{- end -}}

{{- define "tidb.tidb.configConstraintName" -}}
tidb-config-constraints
{{- end -}}

{{- define "tidb.tikv.configConstraintName" -}}
tikv-config-constraints
{{- end -}}

{{- define "tidb.pd.configConstraintName" -}}
tidb-pd-config-constraints
{{- end -}}
