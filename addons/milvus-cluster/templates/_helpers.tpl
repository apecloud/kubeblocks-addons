{{/*
Expand the name of the chart.
*/}}
{{- define "milvus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "milvus.fullname" -}}
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
{{- define "milvus.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "milvus.labels" -}}
helm.sh/chart: {{ include "milvus.chart" . }}
{{ include "milvus.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "milvus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "milvus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "clustername" -}}
{{ include "milvus.fullname" .}}
{{- end}}

{{/*
Create the name of the service account to use
*/}}
{{- define "milvus.serviceAccountName" -}}
{{- default (printf "kb-%s" (include "clustername" .)) .Values.serviceAccount.name }}
{{- end }}

{{/*
External meta storage service reference
*/}}
{{- define "milvus.serviceRef.meta" }}
{{- if eq .Values.storage.meta.mode "serviceref" }}
- name: milvus-meta-storage
  namespace: {{ .Values.storage.meta.serviceRef.namespace }}
  cluster: {{ .Values.storage.meta.serviceRef.cluster }}
  serviceDescriptor: {{ .Values.storage.meta.serviceRef.serviceDescriptor }}
{{- end }}
{{- end }}

{{/*
External log storage service reference
*/}}
{{- define "milvus.serviceRef.log" }}
{{- if eq .Values.storage.log.mode "serviceref" }}
- name: milvus-log-storage
  namespace: {{ .Values.storage.log.serviceRef.namespace }}
  cluster: {{ .Values.storage.log.serviceRef.cluster }}
  serviceDescriptor: {{ .Values.storage.log.serviceRef.serviceDescriptor }}
{{- end }}
{{- end }}

{{/*
External object storage service reference
*/}}
{{- define "milvus.serviceRef.object" }}
{{- if eq .Values.storage.object.mode "serviceref" }}
- name: milvus-object-storage
  namespace: {{ .Values.storage.object.serviceRef.namespace }}
  cluster: {{ .Values.storage.object.serviceRef.cluster }}
  serviceDescriptor: {{ .Values.storage.object.serviceRef.serviceDescriptor }}
{{- end }}
{{- end }}




