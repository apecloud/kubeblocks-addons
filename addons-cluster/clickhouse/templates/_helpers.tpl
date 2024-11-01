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
TLS file
*/}}
{{- define "clickhouse-cluster.tls" }}
tls: {{ $.Values.tls.enabled }}
{{- if $.Values.tls.enabled }}
issuer:
  name: {{ $.Values.tls.issuer }}
  {{- if eq $.Values.tls.issuer "UserProvided" }}
  secretRef:
    name: {{ $.Values.tls.secretName }}
    ca: ca.crt
    cert: tls.crt
    key: tls.key
  {{- end }}
{{- end }}
{{- end }}

{{/*
Define clickhouse componentSpec with ComponentDefinition.
*/}}
{{- define "clickhouse-component" -}}
- name: clickhouse
  componentDef: clickhouse-24
  replicas: {{ $.Values.replicaCount | default 2 }}
  disableExporter: {{ $.Values.disableExporter | default "false" }}
  serviceAccountName: {{ include "clickhouse-cluster.serviceAccountName" $ }}
  systemAccounts:
    - name: admin
      passwordConfig:
        length: 10
        numDigits: 5
        numSymbols: 0
        letterCase: MixedCases
        seed: {{ include "kblib.clusterName" . }}
  {{- with $.Values.tolerations }}
  tolerations: {{ .| toYaml | nindent 4 }}
  {{- end }}
  {{- include "kblib.componentResources" . | indent 2 }}
  {{- include "kblib.componentStorages" . | indent 2 }}
  {{- include "clickhouse-cluster.tls" . | indent 2 }}
{{- end }}

{{/*
Define clickhouse keeper componentSpec with ComponentDefinition.
*/}}
{{- define "ch-keeper-component" -}}
- name: ch-keeper
  componentDef: ch-keeper-24
  replicas: {{ .Values.keeper.replicaCount }}
  {{- with .Values.keeper.tolerations }}
  tolerations: {{ .| toYaml | nindent 4 }}
  {{- end }}
  resources:
    limits:
      cpu: {{ .Values.keeper.cpu | quote }}
      memory: {{ print .Values.keeper.memory "Gi" | quote }}
    requests:
      cpu: {{ .Values.keeper.cpu | quote }}
      memory: {{ print .Values.keeper.memory "Gi" | quote }}
  systemAccounts:
    - name: admin
      passwordConfig:
        length: 10
        numDigits: 5
        numSymbols: 0
        letterCase: MixedCases
        seed: {{ include "kblib.clusterName" . }}
  volumeClaimTemplates:
    - name: data
      spec:
      {{- if .Values.keeper.storageClassName }}
          storageClassName: {{ .Values.keeper.storageClassName | quote }}
          {{- end }}
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: {{ print .Values.keeper.storage "Gi" }}
  {{- include "clickhouse-cluster.tls" . | indent 2 }}
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
    replicas: {{ $.Values.replicaCount | default 2 }}
    disableExporter: {{ $.Values.disableExporter | default "false" }}
    serviceAccountName: {{ include "clickhouse-cluster.serviceAccountName" $ }}
    systemAccounts:
    - name: admin
      passwordConfig:
        length: 10
        numDigits: 5
        numSymbols: 0
        letterCase: MixedCases
        seed: {{ include "kblib.clusterName" . }}
    {{- with $.Values.tolerations }}
    tolerations: {{ .| toYaml | nindent 6 }}
    {{- end }}
    {{- include "kblib.componentResources" . | indent 4 }}
    {{- include "kblib.componentStorages" . | indent 4 }}
    {{- include "clickhouse-cluster.tls" . | indent 4 }}
{{- end }}

{{/*
Define clickhouse componentSpec with compatible ComponentDefinition API
*/}}
{{- define "clickhouse-nosharding-component" -}}
{{- range $i := until (.Values.shardCount | int) }}
- name: shard-{{ $i }}
  componentDef: clickhouse-24
  replicas: {{ $.Values.replicaCount | default 2 }}
  disableExporter: {{ $.Values.disableExporter | default "false" }}
  serviceAccountName: {{ include "clickhouse-cluster.serviceAccountName" $ }}
  {{- with $.Values.tolerations }}
  tolerations: {{ .| toYaml | nindent 4 }}
  {{- end }}
  {{- include "kblib.componentResources" $ | indent 2 }}
  {{- include "kblib.componentStorages" $ | indent 2 }}
  {{- include "clickhouse-cluster.tls" $ | indent 2 }}
{{- end }}
{{- end }}