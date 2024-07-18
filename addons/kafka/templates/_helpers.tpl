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
{{- define "kafka-broker.componentDefName" -}}
{{- if eq (len .Values.clusterVersionOverride) 0 -}}
kafka-broker
{{- else -}}
{{- printf "kafka-broker-%s" .Values.clusterVersionOverride -}}
{{- end -}}
{{- end -}}
