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

{{- define "kafka-cluster.metadata" -}}
- name: metadata
  spec:
    storageClassName: {{ $.Values.metaStorageClassName }}
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: {{ print $.Values.metaStorage "Gi" }}
{{- end }}


{{- define "kafka-cluster.commonSpec" -}}
serviceAccountName: {{ include "kblib.serviceAccountName" .}}
monitor: {{ $.Values.monitorEnable }}
services:
  - name: advertised-listener
  {{- if $.Values.nodePortEnabled }}
    serviceType: NodePort
  {{- else }}
    serviceType: ClusterIP
  {{- end }}
    podService: true
{{- include "kblib.componentResources" . }}
{{- if $.Values.storageEnable }}
volumeClaimTemplates:
  - name: data
    spec:
      storageClassName: {{ $.Values.storageClassName }}
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: {{ print $.Values.storage "Gi" }}
{{- include "kafka-cluster.metadata" . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "kafka-cluster.tls" -}}
tls: {{ $.Values.tlsEnable }}
{{- if $.Values.tlsEnable }}
issuer:
  name: KubeBlocks
{{- end }}
{{- end }}

{{- define "kafka-zookeeper-VCT" -}}
volumeClaimTemplates:
  - name: data
    spec:
      storageClassName: {{ .Values.zookeeper.data.storageClassName }}
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: {{ .Values.zookeeper.data.size }}
  - name: log
    spec:
      storageClassName: {{ .Values.zookeeper.log.storageClassName }}
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: {{ .Values.zookeeper.log.size }}
{{- end }}

{{- define "kafka-cluster.topology" -}}
  {{- if .Values.monitorEnable -}}
    {{- if eq "withZookeeper" $.Values.mode -}}
with_zookeeper_monitor
    {{- else if eq "combined" $.Values.mode -}}
combined_monitor  
    {{- else -}}
separated_monitor
    {{- end -}}
  {{- else -}}
    {{- if eq "withZookeeper" $.Values.mode -}}
with_zookeeper
    {{- else if eq "combined" $.Values.mode -}}
combined
    {{- else -}}
separated
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- define "kafka-cluster.combine-componentSpec" -}}
{{- include "kafka-cluster.tls" . }}
replicas: {{ $.Values.replicas }}
monitor: {{ $.Values.monitorEnable }}
{{- include "kafka-cluster.commonSpec" . | nindent 0 }}
{{- end }}

{{- define "kafka-cluster.broker-componentSpec" -}}
{{- include "kafka-cluster.tls" . }}
replicas: {{ $.Values.brokerReplicas }}
{{- include "kafka-cluster.commonSpec" . | nindent 0}}
{{- end }}

{{- define "kafka-cluster.zookeeper-componentSpec" }}
replicas: {{ .Values.zookeeper.replicas }} 
serviceAccountName: {{ include "kblib.serviceAccountName" . }}
{{- include "kblib.componentMonitor" . }}
{{- include "kblib.componentResources" . }}
{{- include "kafka-zookeeper-VCT" . | nindent 0}}
{{- end }}

{{- define "kafka-cluster.controller-componentSpec" -}}
{{- include "kafka-cluster.tls" . }}
replicas: {{ $.Values.controllerReplicas }}
monitor: {{ $.Values.monitorEnable }}
serviceAccountName: {{ include "kblib.serviceAccountName" . }}
{{- include "kblib.componentResources" . }}
{{- if $.Values.storageEnable }}
volumeClaimTemplates:
  {{- include "kafka-cluster.metadata" . | nindent 2 }}
{{- end }}
{{- end }}