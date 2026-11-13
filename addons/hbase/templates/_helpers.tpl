{{/*
Expand the name of the chart.
*/}}
{{- define "hbase.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "hbase.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hbase.labels" -}}
helm.sh/chart: {{ include "hbase.chart" . }}
{{ include "hbase.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hbase.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hbase.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "hbase.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Component definition regex patterns
*/}}
{{- define "hbase.hmasterCmpdRegexPattern" -}}
^hbase-hmaster-\d+\.?\d*$
{{- end }}

{{- define "hbase.hregionserverCmpdRegexPattern" -}}
^hbase-hregionserver-\d+\.?\d*$
{{- end }}

{{- define "hbase.hbaseStandaloneCmpdRegexPattern" -}}
^hbase-standalone-\d+\.?\d*$
{{- end }}

{{/*
Image references
*/}}
{{- define "hbase.hmasterImage" -}}
{{ .Values.hmaster.image.registry }}/{{ .Values.hmaster.image.repository }}:{{ .Values.hmaster.image.tag }}
{{- end }}

{{- define "hbase.hregionserverImage" -}}
{{ .Values.hregionserver.image.registry }}/{{ .Values.hregionserver.image.repository }}:{{ .Values.hregionserver.image.tag }}
{{- end }}

{{- define "hbase.hbaseStandaloneImage" -}}
{{ .Values.hbasestandalone.image.registry }}/{{ .Values.hbasestandalone.image.repository }}:{{ .Values.hbasestandalone.image.tag }}
{{- end }}

{{- define "hbase.jmxExporterImage" -}}
{{ .Values.images.jmxExporter.registry }}/{{ .Values.images.jmxExporter.repository }}:{{ .Values.images.jmxExporter.tag }}
{{- end }}
