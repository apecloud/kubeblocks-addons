{{/*
Chart name
*/}}
{{- define "hadoop.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart name and version for labels
*/}}
{{- define "hadoop.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hadoop.labels" -}}
helm.sh/chart: {{ include "hadoop.chart" . }}
{{ include "hadoop.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hadoop.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hadoop.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "hadoop.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "hadoop.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "hadoop.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Component definition regex patterns
*/}}
{{- define "hadoop.hadoopCoreCmpdRegexPattern" -}}
^hadoop-core$
{{- end }}

{{- define "hadoop.hdfsJournalnodeCmpdRegexPattern" -}}
^hdfs-journalnode$
{{- end }}

{{- define "hadoop.hdfsNamenodeCmpdRegexPattern" -}}
^hdfs-namenode$
{{- end }}

{{- define "hadoop.hdfsDatanodeCmpdRegexPattern" -}}
^hdfs-datanode$
{{- end }}

{{/*
Image references
*/}}
{{- define "hadoop.commonImage" -}}
{{ .Values.image.common.registry }}/{{ .Values.image.common.repository }}:{{ .Values.image.common.tag }}
{{- end }}

{{- define "hadoop.coreImage" -}}
{{ .Values.core.image.registry }}/{{ .Values.core.image.repository }}:{{ .Values.core.image.tag }}
{{- end }}

{{- define "hadoop.journalNodeImage" -}}
{{ .Values.journalNode.image.registry }}/{{ .Values.journalNode.image.repository }}:{{ .Values.journalNode.image.tag }}
{{- end }}

{{- define "hadoop.nameNodeImage" -}}
{{ .Values.nameNode.image.registry }}/{{ .Values.nameNode.image.repository }}:{{ .Values.nameNode.image.tag }}
{{- end }}

{{- define "hadoop.dataNodeImage" -}}
{{ .Values.dataNode.image.registry }}/{{ .Values.dataNode.image.repository }}:{{ .Values.dataNode.image.tag }}
{{- end }}