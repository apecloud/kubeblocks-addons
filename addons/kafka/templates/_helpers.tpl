{{/*
Expand the name of the chart.
*/}}
{{- define "kafka.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kafka.fullname" -}}
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
{{- define "kafka.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kafka.labels" -}}
helm.sh/chart: {{ include "kafka.chart" . }}
{{ include "kafka.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kafka.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kafka.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
Define kafka.combine component definition name
*/}}
{{- define "kafka-combine.componentDefName" -}}
{{- if eq (len .Values.clusterVersionOverride) 0 -}}
kafka-combine
{{- else -}}
{{- printf "kafka-combine-%s" .Values.clusterVersionOverride -}}
{{- end -}}
{{- end -}}

{{/*
Define kafka-exporter component definition name
*/}}
{{- define "kafka-exporter.componentDefName" -}}
{{- if eq (len .Values.clusterVersionOverride) 0 -}}
kafka-exporter
{{- else -}}
{{- printf "kafka-exporter-%s" .Values.clusterVersionOverride -}}
{{- end -}}
{{- end -}}

{{/*
Define kafka-controller component definition name
*/}}
{{- define "kafka-controller.componentDefName" -}}
{{- if eq (len .Values.clusterVersionOverride) 0 -}}
kafka-controller
{{- else -}}
{{- printf "kafka-controller-%s" .Values.clusterVersionOverride -}}
{{- end -}}
{{- end -}}

{{/*
Define kafka-broker component definition name
*/}}
{{- define "kafka-broker2_8.componentDefName" -}}
{{- if eq (len .Values.clusterVersionOverride) 0 -}}
kafka-broker-2.8
{{- else -}}
{{- printf "kafka-broker-2.8-%s" .Values.clusterVersionOverride -}}
{{- end -}}
{{- end -}}

{{- define "kafka-broker3_2.componentDefName" -}}
{{- if eq (len .Values.clusterVersionOverride) 0 -}}
kafka-broker-3.2
{{- else -}}
{{- printf "kafka-broker-3.2-%s" .Values.clusterVersionOverride -}}
{{- end -}}
{{- end -}}


{{- define "kafka-zookeeper.componentDefName" -}}
{{- if eq (len .Values.clusterVersionOverride) 0 -}}
kafka-zookeeper
{{- else -}}
{{- printf "kafka-zookeeper-%s" .Values.clusterVersionOverride -}}
{{- end -}}
{{- end -}}

{{- define "kafka.cm.common.metadata" -}}
namespace: {{ .Release.Namespace | quote }}
labels:
  {{- include "common.labels.standard" . | nindent 2 }}
  {{- if .Values.commonLabels }}
  {{- include "common.tplvalues.render" ( dict "value" .Values.commonLabels "context" $ ) | nindent 2 }}
  {{- end }}
{{- if .Values.commonAnnotations }}
annotations:
  {{- include "common.tplvalues.render" ( dict "value" .Values.commonAnnotations "context" $ ) | nindent 2 }}
{{- end }}
{{- end -}}