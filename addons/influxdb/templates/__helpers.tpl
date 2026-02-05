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
{{- define "influxdb.standalone.cmpdName" -}}
influxdb-{{ .Chart.Version }}
{{- end -}}

{{- define "influxdb.standalone.cmpdRegexpPattern" -}}
^influxdb-\d+
{{- end -}}

{{- define "influxdb.meta.cmpdName" -}}
influxdb-meta-{{ .Chart.Version }}
{{- end -}}

{{- define "influxdb.meta.cmpdRegexpPattern" -}}
^influxdb-meta-
{{- end -}}

{{- define "influxdb.data.cmpdName" -}}
influxdb-data-{{ .Chart.Version }}
{{- end -}}

{{- define "influxdb.data.cmpdRegexpPattern" -}}
^influxdb-data-
{{- end -}}

{{/*
Define influxdb configuration template name
*/}}
{{- define "influxdb.standalone.configurationTemplate" -}}
influxdb-configuration
{{- end -}}

{{- define "influxdb.meta.configurationTemplate" -}}
influxdb-meta-configuration-tpl
{{- end -}}

{{- define "influxdb.data.configurationTemplate" -}}
influxdb-data-configuration-tpl
{{- end -}}

{{- define "influxdb.prcName" -}}
influxdb-pcr-{{ .Chart.Version }}
{{- end -}}

{{- define "influxdb.pdName" -}}
influxdb-pd
{{- end -}}

{{- define "influxdb.cmScriptsName" -}}
influxdb-scripts-{{ .Chart.Version }}
{{- end -}}
