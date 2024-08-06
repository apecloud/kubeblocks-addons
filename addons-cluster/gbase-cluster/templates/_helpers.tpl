{{/*
Expand the name of the chart.
*/}}
{{- define "gbase-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "gbase-cluster.fullname" -}}
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
Expand the namespace of the chart.
*/}}
{{- define "gbase-cluster.namespace" -}}
{{ .Release.Namespace }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "gbase-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
gbase cluster labels
*/}}
{{- define "gbase-cluster.labels" -}}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "gbase-cluster.chart" . }}
{{- end }}

{{/*
Define replicas.
*/}}
{{- define "gbase-cluster.replicas" }}
{{- if eq .Values.mode "standalone" }}
{{- 1 }}
{{- else }}
{{- .Component.replicas }}
{{- end }}
{{- end -}}

{{- define "gbase-cluster.volumeClaimTemplates" }}
volumeClaimTemplates:
  - name: data
    spec:
      storageClassName: {{ .Values.storageClassName }}
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: {{ .Component.dataStorage }}
{{- end -}}

{{- define "gbase-cluster.resources" }}
resources:
  limits:
    cpu: {{ .Component.resources.limits.cpu | quote }}
    memory: {{ .Component.resources.limits.memory | quote }}
  requests:
    cpu: {{ .Component.resources.requests.cpu | quote }}
    memory: {{ .Component.resources.requests.memory | quote }}
{{- end -}}

{{- define "gbase-cluster.volumes" }}
volumes:
  - name: ssh-key
    secret:
      secretName: {{ .Values.sshKeySecret }}
{{- end -}}

{{/*
gbase replication mode
*/}}
{{- define "gbase-cluster.replication.specs" }}
{{- $component := .Values.replication }}
- name: gbase-replica
  replicas: {{ include "gbase-cluster.replicas" (dict "Values" .Values "Component" $component) }}
  {{ include "gbase-cluster.volumes" . | indent 2 }}
  {{ include "gbase-cluster.resources" (dict "Values" .Values "Component" $component) | indent 2 }}
  {{ include "gbase-cluster.volumeClaimTemplates" (dict "Values" .Values "Component" $component) | indent 2 }}
{{- end -}}
