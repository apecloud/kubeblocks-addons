{{/*
Expand the name of the chart.
*/}}
{{- define "kafka-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kafka-cluster.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-cluster" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kafka-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kafka-cluster.labels" -}}
helm.sh/chart: {{ include "kafka-cluster.chart" . }}
{{ include "kafka-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kafka-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kafka-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "clustername" -}}
{{ include "kafka-cluster.fullname" .}}
{{- end}}

{{/*
Create the name of the service account to use
*/}}
{{- define "kafka-cluster.serviceAccountName" -}}
{{- default (printf "kb-%s" (include "clustername" .)) .Values.serviceAccount.name }}
{{- end }}

{{/*
Define kafka broker component name
*/}}
{{- define "kafka-cluster.brokerComponent" -}}
{{- if eq .Values.mode "combined" }}
{{- printf "kafka-combine" -}}
{{ else }}
{{- printf "kafka-broker" -}}
{{- end }}
{{- end }}

{{/*
Define kafka cluster annotation keys for nodeport feature gate.
*/}}
{{- define "kafka-cluster.brokerAddrFeatureGate" -}}
kubeblocks.io/enabled-pod-ordinal-svc: broker
{{- if .Values.nodePortEnabled }}
kubeblocks.io/enabled-node-port-svc: broker
kubeblocks.io/disabled-cluster-ip-svc: broker
{{- end }}
{{- end }}

{{/*
Define kafka-exporter resources
*/}}
{{- define "kafka-exporter.resources" }}
{{- $requestCPU := (float64 .Values.monitor.request.cpu) }}
{{- $requestMemory := (float64 .Values.monitor.request.memory) }}
{{- $limitCPU := (float64 .Values.monitor.limit.cpu) }}
{{- $limitMemory := (float64 .Values.monitor.limit.memory) }}
resources:
  limits:
    cpu: {{ $limitCPU | quote }}
    memory: {{ print $limitMemory "Gi" | quote }}
  requests:
    cpu: {{ $requestCPU | quote }}
    memory: {{ print $requestMemory "Gi" | quote }}
{{- end }}