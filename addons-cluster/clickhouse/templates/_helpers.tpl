{{/*
Expand the name of the chart.
*/}}
{{- define "clickhouse-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "clickhouse-cluster.fullname" -}}
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
{{- define "clickhouse-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "clickhouse-cluster.labels" -}}
helm.sh/chart: {{ include "clickhouse-cluster.chart" . }}
{{ include "clickhouse-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "clickhouse-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clickhouse-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "clustername" -}}
{{ .Release.Name }}
{{- end}}

{{/*
Create the name of the service account to use
*/}}
{{- define "clickhouse-cluster.serviceAccountName" -}}
{{- default (printf "kb-%s" (include "clustername" .)) .Values.serviceAccount.name }}
{{- end }}

{{/*
Define clickhouse componentSpec with ComponentDefinition.
*/}}
{{- define "clickhouse-ch-component" -}}
- name: clickhouse
  componentDef: clickhouse-24
  replicas: {{ $.Values.clickhouse.replicaCount | default 2 }}
  serviceAccountName: {{ include "clickhouse-cluster.serviceAccountName" $ }}
  {{- with $.Values.clickhouse.tolerations }}
  tolerations: {{ .| toYaml | nindent 8 }}
  {{- end }}
  {{- with $.Values.clickhouse.resources }}
  resources:
    limits:
      cpu: {{ .limits.cpu | quote }}
      memory: {{ .limits.memory | quote }}
    requests:
      cpu: {{ .requests.cpu | quote }}
      memory: {{ .requests.memory | quote }}
  {{- end }}
  volumeClaimTemplates:
    - name: data
      spec:
        storageClassName: {{ $.Values.clickhouse.persistence.data.storageClassName }}
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: {{ $.Values.clickhouse.persistence.data.size }}
{{- end }}

{{/*
Define clickhouse keeper componentSpec with ComponentDefinition.
*/}}
{{- define "clickhouse-keeper-component" -}}
- name: ch-keeper
  componentDef: ch-keeper-24
  replicas: {{ .Values.keeper.replicaCount }}
  {{- with .Values.clickhouse.tolerations }}
  tolerations: {{ .| toYaml | nindent 8 }}
  {{- end }}
  {{- with $.Values.keeper.resources }}
  resources:
    limits:
      cpu: {{ .limits.cpu | quote }}
      memory: {{ .limits.memory | quote }}
    requests:
      cpu: {{ .requests.cpu | quote }}
      memory: {{ .requests.memory | quote }}
  {{- end }}
  volumeClaimTemplates:
    - name: data
      spec:
        storageClassName: {{ $.Values.keeper.persistence.data.storageClassName }}
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: {{ $.Values.keeper.persistence.data.size }}
{{- end }}

{{/*
Define clickhouse shardingComponentSpec with ComponentDefinition.
*/}}
{{- define "clickhouse-sharding-component" -}}
- name: shard
  shards: {{ .Values.shardCount }}
  template:
    name: clickhouse
    componentDef: clickhouse-24
    replicas: {{ $.Values.clickhouse.replicaCount | default 2 }}
    serviceAccountName: {{ include "clickhouse-cluster.serviceAccountName" $ }}
    {{- with $.Values.clickhouse.tolerations }}
    tolerations: {{ .| toYaml | nindent 8 }}
    {{- end }}
    {{- with $.Values.clickhouse.resources }}
    resources:
      limits:
        cpu: {{ .limits.cpu | quote }}
        memory: {{ .limits.memory | quote }}
      requests:
        cpu: {{ .requests.cpu | quote }}
        memory: {{ .requests.memory | quote }}
    {{- end }}
    volumeClaimTemplates:
      - name: data
        spec:
          storageClassName: {{ $.Values.clickhouse.persistence.data.storageClassName }}
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: {{ $.Values.clickhouse.persistence.data.size }}
{{- end }}

{{/*
Define clickhouse componentSpec with compatible ComponentDefinition API
*/}}
{{- define "clickhouse-nosharding-component" -}}
{{- range $i := until (.Values.shardCount | int) }}
- name: shard-{{ $i }}
  componentDef: clickhouse-24
  replicas: {{ $.Values.clickhouse.replicaCount | default 2 }}
  disableExporter: false
  serviceAccountName: {{ include "clickhouse-cluster.serviceAccountName" $ }}
  {{- with $.Values.clickhouse.tolerations }}
  tolerations: {{ .| toYaml | nindent 8 }}
  {{- end }}
  {{- with $.Values.clickhouse.resources }}
  resources:
    limits:
      cpu: {{ .limits.cpu | quote }}
      memory: {{ .limits.memory | quote }}
    requests:
      cpu: {{ .requests.cpu | quote }}
      memory: {{ .requests.memory | quote }}
  {{- end }}
  volumeClaimTemplates:
    - name: data
      spec:
        storageClassName: {{ $.Values.clickhouse.persistence.data.storageClassName }}
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: {{ $.Values.clickhouse.persistence.data.size }}
{{- end }}
{{- end }}