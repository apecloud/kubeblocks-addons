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


{{- define "kafka.topology" -}}
{{- if eq "combined" .Values.mode -}}
  {{- if .Values.monitorEnable -}}
    combined_monitor
  {{- else -}}
    combined
  {{- end -}}
{{- else if eq "separated" .Values.mode -}}
  {{- if .Values.monitorEnable -}}
    separated_monitor
  {{- else -}}
    separated
  {{- end -}}
{{- else -}}
kafka2-external-zk
{{- end -}}
{{- end -}}

{{- define "kafka-cluster.brokerCommonEnv" -}}
- name: KB_KAFKA_ENABLE_SASL
  value: "{{ .Values.saslEnable }}"
- name: KB_KAFKA_BROKER_HEAP
  value: "{{ .Values.brokerHeap }}"
- name: KB_KAFKA_CONTROLLER_HEAP
  value: "{{ .Values.controllerHeap }}"
- name: KB_BROKER_DIRECT_POD_ACCESS
  {{- if .Values.fixedPodIPEnabled }}
  value: "true"
  {{- else }}
  value: "false"
  {{- end }}
{{- end -}}

{{- define "kafka-cluster.brokerVCT" -}}
{{- if .Values.storageEnable }}
volumeClaimTemplates:
  - name: data
    spec:
      storageClassName: {{ .Values.storageClassName }}
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: {{ print .Values.storage "Gi" }}
  - name: metadata
    spec:
      storageClassName: {{ .Values.metaStorageClassName }}
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: {{ print .Values.metaStorage "Gi" }}
{{- end }}
{{- end -}}

{{- define "kafka-cluster.controllerVCT" -}}
{{- if .Values.storageEnable }}
volumeClaimTemplates:
  - name: metadata
    spec:
      storageClassName: {{ .Values.metaStorageClassName }}
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: {{ print .Values.metaStorage "Gi" }}
{{- end }}
{{- end -}}

