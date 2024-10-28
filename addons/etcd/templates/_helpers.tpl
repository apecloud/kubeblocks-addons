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
helm.sh/resource-policy: keep
{{- end }}

{{/*
Define etcd 3.X component definition name
*/}}
{{- define "etcd3.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.major3.minorAll ) 0 -}}
etcd-3-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.major3.minorAll -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define etcd component definition regular expression name prefix
*/}}
{{- define "etcd.cmpdRegexpPattern" -}}
^etcd-\d+
{{- end -}}

{{/*
Define etcd 3.X component configuration template name
*/}}
{{- define "etcd3.configurationTemplate" -}}
etcd3-config-template-{{ .Chart.Version }}
{{- end }}

{{/*
Define etcd 3.X component config constriant name
*/}}
{{- define "etcd3.configConstraint" -}}
etcd3-config-constraints
{{- end }}

{{/*
Define etcd 3.X component script template name
*/}}
{{- define "etcd3.scriptsTemplate" -}}
etcd3-scripts-template-{{.Chart.Version}}
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
etcdctl-backup
{{- end -}}
