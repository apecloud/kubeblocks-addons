{{/*
Expand the name of the chart.
*/}}
{{- define "pgbouncer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pgbouncer.fullname" -}}
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
{{- define "pgbouncer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pgbouncer.labels" -}}
helm.sh/chart: {{ include "pgbouncer.chart" . }}
{{ include "pgbouncer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "pgbouncer.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "pgbouncer.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "pgbouncer.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pgbouncer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pgbouncer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "pgbouncer.componentDefNamePrefix" -}}
pgbouncer-proxy-
{{- end -}}
{{- define "pgbouncer.componentDefName" -}}
pgbouncer-proxy-{{ .Chart.Version }}
{{- end -}}
{{- define "pgbouncer.componentVersionName" -}}
pgbouncer-proxy
{{- end -}}
{{- define "pgbouncer.configurationTemplate" -}}
pgbouncer-configuration-{{ .Chart.Version }}
{{- end -}}
{{- define "pgbouncer.parametersDefinition" -}}
pgbouncer-pd-{{ .Chart.Version }}
{{- end -}}
{{- define "pgbouncer.pcr" -}}
pgbouncer-pcr-{{ .Chart.Version }}
{{- end -}}
{{- define "pgbouncer.scriptsTemplate" -}}
pgbouncer-scripts-{{ .Chart.Version }}
{{- end -}}
{{- define "pgbouncer.defaultServiceVersion" -}}
{{- $version := "" -}}
{{- range .Values.versions -}}
{{- if .isDefault -}}
{{- if $version -}}{{ fail "versions must contain exactly one default version" }}{{- end -}}
{{- $version = .version -}}
{{- end -}}
{{- end -}}
{{- required "versions must contain exactly one default version" $version -}}
{{- end -}}
{{- define "pgbouncer.componentImageByVersion" -}}
{{- printf "%s/%s:%s" (.root.Values.image.registry | default "docker.io") .root.Values.image.repository .tag -}}
{{- end -}}
