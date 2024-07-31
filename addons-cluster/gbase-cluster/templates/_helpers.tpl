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
{{- .Component.replicas }}
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

{{/*
gbase replication mode
*/}}
{{- define "gbase-cluster.single.specs" }}
{{- $component := .Values.replication }}
- name: gbase-single
  replicas: {{ include "gbase-cluster.replicas" (dict "Values" .Values "Component" $component) }}
  {{ include "gbase-cluster.resources" (dict "Values" .Values "Component" $component) | indent 2 }}
  {{ include "gbase-cluster.volumeClaimTemplates" (dict "Values" .Values "Component" $component) | indent 2 }}
{{- end -}}


{{- define "gbase-cluster.datanode.shard.specs" }}
{{- $component := .Values.distribution.datanode }}
- name: datanode-shard
  shards: {{ .Values.distribution.datanode.shardCount }}
  template:
    name: gbase-datanode
    componentDef: gbase-datanode
    replicas: {{ include "gbase-cluster.replicas" (dict "Values" .Values "Component" $component) }}
    {{ include "gbase-cluster.resources" (dict "Values" .Values "Component" $component) | indent 4 }}
    {{ include "gbase-cluster.volumeClaimTemplates" (dict "Values" .Values "Component" $component) | indent 4 }}
{{- end -}}

{{- define "gbase-cluster.datanode.specs" }}
{{- $component := .Values.distribution.datanode }}
- name: gbase-datanode
  replicas: {{ include "gbase-cluster.replicas" (dict "Values" .Values "Component" $component) }}
  {{ include "gbase-cluster.resources" (dict "Values" .Values "Component" $component) | indent 2 }}
  {{ include "gbase-cluster.volumeClaimTemplates" (dict "Values" .Values "Component" $component) | indent 2 }}
{{- end -}}

{{- define "gbase-cluster.ghaServer.specs" }}
{{- $component := .Values.distribution.gha_server }}
- name: gbase-gha-server
  replicas: {{ include "gbase-cluster.replicas" (dict "Values" .Values "Component" $component) }}
  {{ include "gbase-cluster.resources" (dict "Values" .Values "Component" $component) | indent 2 }}
  {{ include "gbase-cluster.volumeClaimTemplates" (dict "Values" .Values "Component" $component) | indent 2 }}
{{- end -}}

{{- define "gbase-cluster.dcs.specs" }}
{{- $component := .Values.distribution.dcs }}
- name: gbase-dcs
  replicas: {{ include "gbase-cluster.replicas" (dict "Values" .Values "Component" $component) }}
  {{ include "gbase-cluster.resources" (dict "Values" .Values "Component" $component) | indent 2 }}
  {{ include "gbase-cluster.volumeClaimTemplates" (dict "Values" .Values "Component" $component) | indent 2 }}
{{- end -}}

{{- define "gbase-cluster.gtm.specs" }}
{{- $component := .Values.distribution.gtm }}
- name: gbase-gtm
  replicas: {{ include "gbase-cluster.replicas" (dict "Values" .Values "Component" $component) }}
  {{ include "gbase-cluster.resources" (dict "Values" .Values "Component" $component) | indent 2 }}
  {{ include "gbase-cluster.volumeClaimTemplates" (dict "Values" .Values "Component" $component) | indent 2 }}
{{- end -}}

{{- define "gbase-cluster.coord.specs" }}
{{- $component := .Values.distribution.coordinator }}
- name: gbase-coord
  replicas: {{ include "gbase-cluster.replicas" (dict "Values" .Values "Component" $component) }}
  {{ include "gbase-cluster.resources" (dict "Values" .Values "Component" $component) | indent 2 }}
  {{ include "gbase-cluster.volumeClaimTemplates" (dict "Values" .Values "Component" $component) | indent 2 }}
{{- end -}}