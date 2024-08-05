{{/*
Expand the name of the chart.
*/}}
{{- define "risingwave-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "risingwave-cluster.fullname" -}}
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
{{- define "risingwave-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "risingwave-cluster.labels" -}}
helm.sh/chart: {{ include "risingwave-cluster.chart" . }}
{{ include "risingwave-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "risingwave-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "risingwave-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "clustername" -}}
{{ include "risingwave-cluster.fullname" .}}
{{- end}}

{{/*
Create the name of the service account to use
*/}}
{{- define "risingwave-cluster.serviceAccountName" -}}
{{- default .Values.risingwave.stateStore.s3.authentication.serviceAccountName .Values.serviceAccount.name }}
{{- end }}

{{/*
Create the hummock option
*/}}
{{- define "risingwave-cluster.options.hummock" }}
hummock+s3://{{ .Values.risingwave.stateStore.s3 }}
{{- end }}

{{/*
Cluster envs.
*/}}
{{- define "risingwave-cluster.envs" }}
- name: RW_STATE_STORE
  value: hummock+s3://{{ .Values.risingwave.stateStore.s3.bucket }}
- name: AWS_REGION
  value: {{ .Values.risingwave.stateStore.s3.region }}
{{- if eq .Values.risingwave.stateStore.s3.authentication.serviceAccountName "" }}
- name: AWS_ACCESS_KEY_ID
  value: {{ .Values.risingwave.stateStore.s3.authentication.accessKey }}
- name: AWS_SECRET_ACCESS_KEY
  value: {{ .Values.risingwave.stateStore.s3.authentication.secretAccessKey }}
{{- end }}
- name: RW_DATA_DIRECTORY
  value: {{ .Values.risingwave.stateStore.dataDirectory }}
{{- if .Values.risingwave.stateStore.s3.endpoint }}
- name: RW_S3_ENDPOINT
  value: {{ .Values.risingwave.stateStore.s3.endpoint }}
{{- end }}
{{- if .Values.risingwave.metaStore.etcd.authentication.enabled }}
- name: RW_ETCD_USERNAME
  value: {{ .Values.risingwave.metaStore.etcd.authentication.username }}
- name: RW_ETCD_PASSWORD
  value: {{ .Values.risingwave.metaStore.etcd.authentication.password }}
{{- end }}
- name: RW_ETCD_ENDPOINTS
  value: {{ .Values.risingwave.metaStore.etcd.endpoints }}
- name: RW_ETCD_AUTH
  value: {{ .Values.risingwave.metaStore.etcd.authentication.enabled}}
{{- end }}