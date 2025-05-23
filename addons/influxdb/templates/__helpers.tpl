{{/*
Expand the name of the chart.
*/}}
{{- define "influxdb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "influxdb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "influxdb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "influxdb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "influxdb.labels" -}}
helm.sh/chart: {{ include "influxdb.chart" . }}
{{ include "influxdb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "influxdb.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "influxdb.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "influxdb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define influxdb component definition name
*/}}
{{- define "influxdb.cmpdName" -}}
influxdb-{{ .Chart.Version }}
{{- end -}}

{{/*
Define influxdb component definition regex pattern
*/}}
{{- define "influxdb.cmpdRegexpPattern" -}}
^influxdb-
{{- end -}}
