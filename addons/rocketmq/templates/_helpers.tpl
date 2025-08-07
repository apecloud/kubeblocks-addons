{{/*
Expand the name of the chart.
*/}}
{{- define "rocketmq.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "rocketmq.fullname" -}}
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
{{- define "rocketmq.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rocketmq.labels" -}}
helm.sh/chart: {{ include "rocketmq.chart" . }}
{{ include "rocketmq.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "rocketmq.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rocketmq.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "rocketmq.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "rocketmq.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "rocketmq.annotations" -}}
{{ include "rocketmq.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "rocketmq.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}


{{/*
controller
*/}}
{{- define "rocketmq.controller.fullname" -}}
{{ include "rocketmq.fullname" . }}-controller
{{- end -}}

{{/*
controller
*/}}
{{- define "rocketmq.enableControllerInNamesrv" -}}
{{- if and .Values.controllerModeEnabled (not .Values.controller.enabled) -}}
{{- print "true" -}}
{{- else -}}
{{- print "false" -}}
{{- end -}}
{{- end -}}

{{/*
rocketmq.controller.dlegerPeers
*/}}
{{- define "rocketmq.controller.dlegerPeers" -}}
{{- $address := list -}}
  {{- $fullName := include "rocketmq.controller.fullname" . -}}
  {{- $headlessDomain := printf "%s.%s.svc" $fullName .Release.Namespace -}}
  {{- $replicaCount := int .Values.controller.replicaCount -}}
{{- if eq (include "rocketmq.enableControllerInNamesrv" .) "true" -}}
  {{- $fullName = include "rocketmq.nameserver.fullname" . -}}
  {{- $headlessDomain = printf "%s-headless.%s.svc" $fullName .Release.Namespace -}}
  {{- $replicaCount = int .Values.nameserver.replicaCount -}}
{{- end -}}
  {{- range $i := until $replicaCount -}}
  {{- $address = printf "n%d-%s-%d.%s:9878" $i $fullName $i $headlessDomain | append $address -}}
  {{- end -}}
{{- join ";" $address -}}
{{- end -}}

{{/*
env NAMESRV_ADDR
*/}}
{{- define "rocketmq.nameserver.addr" -}}
{{- $headlessDomain := printf "svc-headless.%s.svc" .Release.Namespace -}}
{{- $address := list -}}
{{- $replicaCount := int .Values.nameserver.replicaCount -}}
  {{- range $i := until $replicaCount -}}
  {{- $address = printf "svc-%d.%s:9876" $i $headlessDomain | append $address -}}
  {{- end -}}
{{- join ";" $address -}}
{{- end -}}
