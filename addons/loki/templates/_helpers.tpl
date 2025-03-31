{{/*
Expand the name of the chart.
*/}}
{{- define "loki.name" -}}
{{- $default := ternary "enterprise-logs" "loki" .Values.enterprise.enabled }}
{{- coalesce .Values.nameOverride $default | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "loki.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := include "loki.name" . }}
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
{{- define "loki.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "loki.labels" -}}
helm.sh/chart: {{ include "loki.chart" . }}
{{ include "loki.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "loki.selectorLabels" -}}
app.kubernetes.io/name: {{ include "loki.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "loki.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "loki.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "loki.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Base template for building docker image reference
*/}}
{{- define "loki.baseImage" }}
{{- $registry := .global.registry | default .service.registry -}}
{{- $repository := .service.repository -}}
{{- $tag := .service.tag | default .defaultVersion | toString -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- end -}}

{{/*
Docker image name for Loki
*/}}
{{- define "loki.lokiImage" -}}
{{- $dict := dict "service" .Values.loki.image "global" .Values.global.image "defaultVersion" .Chart.AppVersion -}}
{{- include "loki.baseImage" $dict -}}
{{- end -}}

{{/*
Docker image name for enterprise logs
*/}}
{{- define "loki.enterpriseImage" -}}
{{- $dict := dict "service" .Values.enterprise.image "global" .Values.global.image "defaultVersion" .Values.enterprise.version -}}
{{- include "loki.baseImage" $dict -}}
{{/* {{- printf "foo" -}} */}}
{{- end -}}

{{/*
Docker image name
*/}}
{{- define "loki.image" -}}
{{- if .Values.enterprise.enabled -}}{{- include "loki.enterpriseImage" . -}}{{- else -}}{{- include "loki.lokiImage" . -}}{{- end -}}
{{- end -}}

{{/*
write fullname
*/}}
{{- define "loki.writeFullname" -}}
{{ include "loki.name" . }}-write
{{- end }}

{{/*
read fullname
*/}}
{{- define "loki.readFullname" -}}
{{ include "loki.name" . }}-read
{{- end }}

{{/*
backend fullname
*/}}
{{- define "loki.backendFullname" -}}
{{ include "loki.name" . }}-backend
{{- end }}

{{/*
gateway fullname
*/}}
{{- define "loki.gatewayFullname" -}}
{{ include "loki.fullname" . }}-gateway
{{- end }}

{{/*
gateway common labels
*/}}
{{- define "loki.gatewayLabels" -}}
{{ include "loki.labels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{/*
gateway selector labels
*/}}
{{- define "loki.gatewaySelectorLabels" -}}
{{ include "loki.selectorLabels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{/*
gateway auth secret name
*/}}
{{- define "loki.gatewayAuthSecret" -}}
{{ .Values.gateway.basicAuth.existingSecret | default (include "loki.gatewayFullname" . ) }}
{{- end }}

{{/*
gateway Docker image
*/}}
{{- define "loki.gatewayImage" -}}
{{- $dict := dict "service" .Values.gateway.image "global" .Values.global.image -}}
{{- include "loki.baseImage" $dict -}}
{{- end }}

{{/*
gateway priority class name
*/}}
{{- define "loki.gatewayPriorityClassName" -}}
{{- $pcn := coalesce .Values.global.priorityClassName .Values.gateway.priorityClassName -}}
{{- if $pcn }}
priorityClassName: {{ $pcn }}
{{- end }}
{{- end }}

{{/*
distributor fullname
*/}}
{{- define "loki.distributorFullname" -}}
{{ include "loki.fullname" . }}-distributor
{{- end }}

{{/*
ingester fullname
*/}}
{{- define "loki.ingesterFullname" -}}
{{ include "loki.fullname" . }}-ingester
{{- end }}

{{/*
query-frontend fullname
*/}}
{{- define "loki.queryFrontendFullname" -}}
{{ include "loki.fullname" . }}-query-frontend
{{- end }}

{{/*
index-gateway fullname
*/}}
{{- define "loki.indexGatewayFullname" -}}
{{ include "loki.fullname" . }}-index-gateway
{{- end }}

{{/*
ruler fullname
*/}}
{{- define "loki.rulerFullname" -}}
{{ include "loki.fullname" . }}-ruler
{{- end }}

{{/*
compactor fullname
*/}}
{{- define "loki.compactorFullname" -}}
{{ include "loki.fullname" . }}-compactor
{{- end }}

{{/*
query-scheduler fullname
*/}}
{{- define "loki.querySchedulerFullname" -}}
{{ include "loki.fullname" . }}-query-scheduler
{{- end }}

{{/*
Define loki backend component definition name
*/}}
{{- define "loki.backendCmpdName" -}}
loki-backend-{{ .Chart.Version }}
{{- end -}}

{{/*
Define loki backend component definition regular expression name prefix
*/}}
{{- define "loki.backendCmpdRegexpPattern" -}}
^loki-backend-
{{- end -}}

{{/*
Define loki gateway component definition name
*/}}
{{- define "loki.gatewayCmpdName" -}}
loki-gateway-{{ .Chart.Version }}
{{- end -}}

{{/*
Define loki backend component definition regular expression name prefix
*/}}
{{- define "loki.gatewayCmpdRegexpPattern" -}}
^loki-gateway-
{{- end -}}

{{/*
Define loki read component definition name
*/}}
{{- define "loki.readCmpdName" -}}
loki-read-{{ .Chart.Version }}
{{- end -}}

{{/*
Define loki read component definition regular expression name prefix
*/}}
{{- define "loki.readCmpdRegexpPattern" -}}
^loki-read-
{{- end -}}


{{/*
Define loki write component definition name
*/}}
{{- define "loki.writeCmpdName" -}}
loki-write-{{ .Chart.Version }}
{{- end -}}

{{/*
Define loki write component definition regular expression name prefix
*/}}
{{- define "loki.writeCmpdRegexpPattern" -}}
^loki-write-
{{- end -}}

{{/*
Define loki write parameter config renderer name
*/}}
{{- define "loki.writePCRName" -}}
loki-write-pcr-{{ .Chart.Version }}
{{- end -}}

{{/*
Define loki backend parameter config renderer name
*/}}
{{- define "loki.backendPCRName" -}}
loki-backend-pcr-{{ .Chart.Version }}
{{- end -}}

{{/*
Define loki read parameter config renderer name
*/}}
{{- define "loki.readPCRName" -}}
loki-read-pcr-{{ .Chart.Version }}
{{- end -}}