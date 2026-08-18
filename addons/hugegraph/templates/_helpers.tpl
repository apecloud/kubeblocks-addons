{{/* Chart and resource names. */}}
{{- define "hugegraph.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "hugegraph.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "hugegraph.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hugegraph.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "hugegraph.labels" -}}
helm.sh/chart: {{ include "hugegraph.chart" . }}
{{ include "hugegraph.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hugegraph.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{- define "hugegraph.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "hugegraph.apiVersion" . }}
{{- end }}

{{- define "hugegraph.cmpdName" -}}
hugegraph-{{ .Chart.Version }}
{{- end }}

{{- define "hugegraph.cmpdPattern" -}}
^hugegraph-
{{- end }}

{{- define "hugegraph.scriptsTemplateName" -}}
hugegraph-scripts-template
{{- end }}

{{- define "hugegraph.actionSetName" -}}
hugegraph-checkpoint-br
{{- end }}

{{- define "hugegraph.backupPolicyTemplateName" -}}
hugegraph-backup-policy-template
{{- end }}

{{- define "hugegraph.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}

{{- define "hugegraph.exporterImage" -}}
{{ .Values.exporter.image.registry | default "docker.io" }}/{{ .Values.exporter.image.repository }}:{{ .Values.exporter.image.tag }}
{{- end }}
