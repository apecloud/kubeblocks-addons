{{/*
Expand the name of the chart.
*/}}
{{- define "hive.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hive.fullname" -}}
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
{{- define "hive.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hive.labels" -}}
helm.sh/chart: {{ include "hive.chart" . }}
{{ include "hive.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hive.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hive.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "hive.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "hive.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Common annotations
*/}}
{{- define "hive.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "hive.apiVersion" . }}
apps.kubeblocks.io/skip-immutable-check: "true"
{{- end }}

{{/*
API version annotation
*/}}
{{- define "hive.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}


{{- define "hive.metastoreCompDef" -}}
hive-metastore-{{ .Chart.Version }}
{{- end }}


{{- define "hive.server2CompDef" -}}
hive-server2-{{ .Chart.Version }}
{{- end }}

{{- define "hive.initJmxExporterContainer" -}}
imagePullPolicy: {{ default "IfNotPresent" .Values.hive.image.pullPolicy }}
command:
- /bin/bash
- -c
- |
  cp /opt/bitnami/jmx-exporter/jmx_prometheus_javaagent.jar /hive/jmx_prometheus_javaagent.jar
  groupadd -g 1000 hadoop
  useradd -u 10000 -g 1000 -m -s /bin/bash hadoop
  chown -R 10000:1000 /hive/jmx_prometheus_javaagent.jar
securityContext:
  runAsUser: 0
  runAsGroup: 0
{{- end }}