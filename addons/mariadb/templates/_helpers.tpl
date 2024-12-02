{{/*
Expand the name of the chart.
*/}}
{{- define "mariadb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mariadb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mariadb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mariadb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mariadb.labels" -}}
helm.sh/chart: {{ include "mariadb.chart" . }}
{{ include "mariadb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Define image
*/}}
{{- define "mariadb.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "mariadb.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}

{{- define "exporter.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.prom.exporter.repository}}
{{- end }}

{{- define "exporter.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.prom.exporter.repository}}:{{.Values.image.prom.exporter.tag}}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "mariadb.annotations" -}}
helm.sh/resource-policy: keep
{{ include "mariadb.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "mariadb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define mariadb component definition name
*/}}
{{- define "mariadb.cmpdName" -}}
mariadb-{{ .Chart.Version }}
{{- end -}}

{{/*
Define mariadb component definition regular expression name prefix
*/}}
{{- define "mariadb.cmpdRegexpPattern" -}}
^mariadb-
{{- end -}}
