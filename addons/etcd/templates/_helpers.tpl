{{/*
Expand the name of the chart.
*/}}
{{- define "etcd.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "etcd.fullname" -}}
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
{{- define "etcd.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "etcd.labels" -}}
helm.sh/chart: {{ include "etcd.chart" . }}
{{ include "etcd.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "etcd.selectorLabels" -}}
app.kubernetes.io/name: {{ include "etcd.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "etcd.annotations" -}}
# {{ include "kblib.helm.resourcePolicy" . }}
{{ include "etcd.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "etcd.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define etcd 3.X component definition name
*/}}
{{- define "etcd3.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.major3 ) 0 -}}
etcd-3-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.major3 -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define etcd component definition regular expression name prefix
*/}}
{{- define "etcd3.cmpdRegexpPattern" -}}
^etcd-3.*
{{- end -}}

{{/*
Define etcd 3.X component config template name
*/}}
{{- define "etcd3.configTemplate" -}}
etcd3-config-template-{{ .Chart.Version }}
{{- end }}

{{/*
Define etcd 3.X component parameters definition name
*/}}
{{- define "etcd3.paramsDefinition" -}}
etcd3-pd
{{- end }}

{{/*
Define etcd 3.X component parameter config renderer name
*/}}
{{- define "etcd3.pcrName" -}}
etcd3-pcr
{{- end }}


{{/*
Define etcd 3.X component script template name
*/}}
{{- define "etcd3.scriptTemplate" -}}
etcd3-script-template-{{.Chart.Version}}
{{- end }}

{{/*
Generate scripts configmap
*/}}
{{- define "etcd.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Define etcdctl backup actionSet name
*/}}
{{- define "etcd.backupActionSet" -}}
etcdctl-br
{{- end -}}

{{/*
Define etcd image repository
*/}}
{{- define "etcd.repository" -}}
{{ .Values.image.registry | default "gcr.io" }}/{{ .Values.image.repository | default "etcd-development/etcd"}}
{{- end }}

{{/*
Define latest etcd image
*/}}
{{- define "etcd3.image" -}}
{{ include "etcd.repository" . }}:{{ .Values.image.tag.major3.minor61 }}
{{- end }}

{{/*
Define bash-busybox image repository
*/}}
{{- define "bashBusyboxImage.repository" -}}
{{ .Values.bashBusyboxImage.registry | default "docker.io" }}/{{ .Values.bashBusyboxImage.repository }}
{{- end }}

{{/*
Define bash-busybox image
*/}}
{{- define "bashBusyboxImage.image" -}}
{{ include "bashBusyboxImage.repository" . }}:{{ .Values.bashBusyboxImage.tag }}
{{- end }}
