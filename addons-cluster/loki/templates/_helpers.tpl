{{/*
Expand the name of the chart.
*/}}
{{- define "loki-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "loki-cluster.fullname" -}}
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

{{- define "clustername" -}}
{{ include "loki-cluster.fullname" .}}
{{- end}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "loki-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "loki-cluster.labels" -}}
helm.sh/chart: {{ include "loki-cluster.chart" . }}
{{ include "loki-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "loki-cluster.selectorLabels" -}}
{{/*app.kubernetes.io/name: {{ include "loki-cluster.name" . }}*/}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
write fullname
*/}}
{{- define "loki-cluster.writeFullname" -}}
{{ include "loki-cluster.name" . }}-write
{{- end }}

{{/*
read fullname
*/}}
{{- define "loki-cluster.readFullname" -}}
{{ include "loki-cluster.name" . }}-read
{{- end }}

{{/*
backend fullname
*/}}
{{- define "loki-cluster.backendFullname" -}}
{{ include "loki-cluster.name" . }}-backend
{{- end }}

{{/*
gateway fullname
*/}}
{{- define "loki-cluster.gatewayFullname" -}}
{{ include "loki-cluster.fullname" . }}-gateway
{{- end }}


{{/*
gateway selector labels
*/}}
{{- define "loki-cluster.gatewaySelectorLabels" -}}
{{ include "loki-cluster.selectorLabels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{/*
gateway auth secret name
*/}}
{{- define "loki-cluster.gatewayAuthSecret" -}}
{{ .Values.gateway.basicAuth.existingSecret | default (include "loki-cluster.gatewayFullname" . ) }}
{{- end }}

{{/*
gateway Docker image
*/}}
{{- define "loki-cluster.gatewayImage" -}}
{{- $dict := dict "service" .Values.gateway.image "global" .Values.global.image -}}
{{- include "loki-cluster.baseImage" $dict -}}
{{- end }}

{{/*
gateway priority class name
*/}}
{{- define "loki-cluster.gatewayPriorityClassName" -}}
{{- $pcn := coalesce .Values.global.priorityClassName .Values.gateway.priorityClassName -}}
{{- if $pcn }}
priorityClassName: {{ $pcn }}
{{- end }}
{{- end }}

{{/*
distributor fullname
*/}}
{{- define "loki-cluster.distributorFullname" -}}
{{ include "loki-cluster.fullname" . }}-distributor
{{- end }}

{{/*
ingester fullname
*/}}
{{- define "loki-cluster.ingesterFullname" -}}
{{ include "loki-cluster.fullname" . }}-ingester
{{- end }}

{{/*
query-frontend fullname
*/}}
{{- define "loki-cluster.queryFrontendFullname" -}}
{{ include "loki-cluster.fullname" . }}-query-frontend
{{- end }}

{{/*
index-gateway fullname
*/}}
{{- define "loki-cluster.indexGatewayFullname" -}}
{{ include "loki-cluster.fullname" . }}-index-gateway
{{- end }}

{{/*
ruler fullname
*/}}
{{- define "loki-cluster.rulerFullname" -}}
{{ include "loki-cluster.fullname" . }}-ruler
{{- end }}

{{/*
compactor fullname
*/}}
{{- define "loki-cluster.compactorFullname" -}}
{{ include "loki-cluster.fullname" . }}-compactor
{{- end }}

{{/*
query-scheduler fullname
*/}}
{{- define "loki-cluster.querySchedulerFullname" -}}
{{ include "loki-cluster.fullname" . }}-query-scheduler
{{- end }}

{{/*
gateway common labels
*/}}
{{- define "loki-cluster.gatewayLabels" -}}
{{ include "loki-cluster.labels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{- define "loki.objectstorage.serviceRef" }}
{{- if eq .Values.storageType "s3" }}
- name: loki-object-storage
  namespace: {{ .Release.Namespace }}
  {{- if not .Values.s3.serviceRef.serviceDescriptor }}
  clusterServiceSelector:
    cluster: {{ .Values.s3.serviceRef.cluster.name }}
    service:
      component: {{ .Values.s3.serviceRef.cluster.component }}
      service: {{ .Values.s3.serviceRef.cluster.service }}
      port: {{ .Values.s3.serviceRef.cluster.port }}
    credential:
      component: {{ .Values.s3.serviceRef.cluster.component }}
      name: {{ .Values.s3.serviceRef.cluster.credential }}
  {{- else }}
  serviceDescriptor: {{ .Values.s3.serviceRef.serviceDescriptor }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "loki-cluster.storageConfig" }}
configs:
  - name: loki-config
    variables:
      storage_type: {{ .Values.storageType }}
      s3_bucket: {{ .Values.s3.bucket }}
      {{/* path is not supported yet
      s3_path: {{ .Values.s3.path }} */}}
      s3_use_path_style: {{ .Values.s3.usePathStyle | quote }}
{{- end -}}

{{- define "loki-cluster.memberlist" }}
services:
  - name: default
    serviceName: memberlist
    spec:
      ports:
        - name: tcp
          port: 7946
          targetPort: http-memberlist
          protocol: TCP
      selector:
        {{- include "loki-cluster.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/part-of: memberlist
{{- end -}}
