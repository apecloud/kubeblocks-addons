{{/*
Expand the name of the chart.
*/}}
{{- define "orioledb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "orioledb.fullname" -}}
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
{{- define "orioledb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "orioledb.labels" -}}
helm.sh/chart: {{ include "orioledb.chart" . }}
{{ include "orioledb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "orioledb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "orioledb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "orioledb.annotations" -}}
helm.sh/resource-policy: keep
{{ include "orioledb.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "orioledb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define orioledb cluster definition name
*/}}
{{- define "orioledb.cdName" -}}
orioledb
{{- end -}}

{{/*
Define orioledb component definition name
*/}}
{{- define "orioledb.cmpdName" -}}
orioledb-{{ .Chart.Version }}
{{- end -}}

{{/*
Define orioledb component version name
*/}}
{{- define "orioledb.cmpvName" -}}
orioledb
{{- end -}}

{{/*
Define orioledb component definition regex pattern
*/}}
{{- define "orioledb.cmpdRegexPattern" -}}
^orioledb-
{{- end -}}

{{/*
Define orioledb component configuration template name
*/}}
{{- define "orioledb.configurationTemplate" -}}
orioledb-configuration-{{ .Chart.Version }}
{{- end -}}

{{/*
Define orioledb component config constraint name
*/}}
{{- define "orioledb.configConstraint" -}}
orioledb-cc-{{ .Chart.Version }}
{{- end -}}

{{/*
Define orioledb pgbouncer configuration template name
*/}}
{{- define "orioledb-pgbouncer.configurationTemplate" -}}
orioledb-pgbouncer-configuration-{{ .Chart.Version }}
{{- end -}}

{{/*
Define orioledb scripts configMap template name
*/}}
{{- define "orioledb.scriptsTemplate" -}}
orioledb-scripts-{{ .Chart.Version }}
{{- end -}}

{{/*
Define orioledb patroni reload scripts template name
*/}}
{{- define "orioledb.patroniReloadScriptsTemplate" -}}
orioledb-patroni-reload-scripts-{{ .Chart.Version }}
{{- end -}}

{{/*
Define orioledb component metrice configuration name
*/}}
{{- define "orioledb.metricsConfiguration" -}}
orioledb-custom-metrics
{{- end -}}

{{/*
Define orioledb component agamotto configuration name
*/}}
{{- define "orioledb.agamottoConfiguration" -}}
orioledb-agamotto-configuration
{{- end -}}

{{/*
Generate scripts configmap
*/}}
{{- define "orioledb.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}
