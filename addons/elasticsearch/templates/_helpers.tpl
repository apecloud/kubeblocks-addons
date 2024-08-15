{{/*
Expand the name of the chart.
*/}}
{{- define "elasticsearch.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "elasticsearch.fullname" -}}
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
{{- define "elasticsearch.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "elasticsearch.labels" -}}
helm.sh/chart: {{ include "elasticsearch.chart" . }}
{{ include "elasticsearch.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "elasticsearch.selectorLabels" -}}
app.kubernetes.io/name: {{ include "elasticsearch.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "elasticsearch.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "elasticsearch.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "elasticsearch-8.1.3.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:8.1.3
{{- end }}

{{- define "elasticsearch-8.8.2.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:8.8.2
{{- end }}

{{- define "elasticsearch-7.10.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:7.10.1
{{- end }}

{{- define "elasticsearch-7.7.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:7.7.1
{{- end }}

{{- define "elasticsearch-7.8.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:7.8.1
{{- end }}

{{- define "elasticsearch-exporter.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.exporter.repository }}:{{ .Values.image.exporter.tag | default "latest" }}
{{- end }}
