{{/*
Expand the name of the chart.
*/}}
{{- define "hadoop.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hadoop.fullname" -}}
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
Create the name of the service account to use
*/}}
{{- define "hadoop.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "hadoop.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Common annotations
*/}}
{{- define "hadoop.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "hadoop.apiVersion" . }}
apps.kubeblocks.io/skip-immutable-check: "true"
{{- end }}

{{/*
API version annotation
*/}}
{{- define "hadoop.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{- define "dataNodeComponentDef" -}}
hadoop-hdfs-datanode-{{ .Chart.Version }}
{{- end }}

{{- define "nameNodeComponentDef" -}}
hadoop-hdfs-namenode-{{ .Chart.Version }}
{{- end }}

{{- define "journalNodeComponentDef" -}}
hadoop-hdfs-journalnode-{{ .Chart.Version }}
{{- end }}

{{- define "coreComponentDef" -}}
hadoop-hdfs-core-{{ .Chart.Version }}
{{- end }}


{{- define "yarnResourceManagerComponentDef" -}}
hadoop-yarn-resourcemanager-{{ .Chart.Version }}
{{- end }}


{{- define "yarnNodeManagerComponentDef" -}}
hadoop-yarn-nodemanager-{{ .Chart.Version }}
{{- end }}