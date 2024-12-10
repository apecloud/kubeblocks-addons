{{/*
Expand the name of the chart.
*/}}
{{- define "opensearch.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "opensearch.fullname" -}}
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
{{- define "opensearch.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "opensearch.labels" -}}
helm.sh/chart: {{ include "opensearch.chart" . }}
{{ include "opensearch.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "opensearch.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opensearch.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "opensearch.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "opensearch.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Define image
*/}}
{{- define "opensearch.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "opensearch.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{- define "dashboard.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.dashboard.repository }}
{{- end }}

{{- define "dashboard.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.dashboard.repository }}:{{ default .Chart.AppVersion .Values.image.dashboard.tag }}
{{- end }}

{{- define "os-master-graceful-handler.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "os-master-graceful-handler.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{- define "fsgroup-volume.image" -}}
{{ .Values.image.registry | default "docker.io" }}/apecloud/alpine:3.16
{{- end }}

{{- define "sysctl.image" -}}
{{ .Values.image.registry | default "docker.io" }}/apecloud/alpine:3.16
{{- end }}

{{/*
Common annotations
*/}}
{{- define "opensearch.annotations" -}}
helm.sh/resource-policy: keep
{{ include "opensearch.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "opensearch.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define opensearch-dashboard component definition name
*/}}
{{- define "opensearch-dashboard.cmpdName" -}}
opensearch-dashboard-{{ .Chart.Version }}
{{- end -}}

{{/*
Define opensearch component definition name
*/}}
{{- define "opensearch.cmpdName" -}}
opensearch-{{ .Chart.Version }}
{{- end -}}

{{/*
Define opensearch component definition regular expression name prefix
*/}}
{{- define "opensearch.cmpdRegexpPattern" -}}
^opensearch-
{{- end -}}

{{/*
Define opensearch-dashboard component definition regular expression name prefix
*/}}
{{- define "opensearch-dashboard.cmpdRegexpPattern" -}}
^opensearch-dashboard-
{{- end -}}

{{/*
Generate scripts configmap
*/}}
{{- define "opensearch.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Define opensearch component script template name
*/}}
{{- define "opensearch.scriptsTemplate" -}}
opensearch-scripts-template-{{ .Chart.Version }}
{{- end -}}
