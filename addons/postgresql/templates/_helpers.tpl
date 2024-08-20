{{/*
Expand the name of the chart.
*/}}
{{- define "postgresql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "postgresql.fullname" -}}
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
{{- define "postgresql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "postgresql.labels" -}}
helm.sh/chart: {{ include "postgresql.chart" . }}
{{ include "postgresql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "postgresql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgresql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Generate scripts configmap
*/}}
{{- define "postgresql.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Define postgresql component definition name prefix
*/}}
{{- define "postgresql.componentDefNamePrefix" -}}
{{- printf "postgresql-" -}}
{{- end -}}

{{/*
Define postgresql12 component definition name
*/}}
{{- define "postgresql.compDefPostgresql12" -}}
{{- if eq (len .Values.componentDefinitionVersion.postgresql12) 0 -}}
postgresql-12
{{- else -}}
{{ include "postgresql.componentDefNamePrefix" . }}{{ .Values.componentDefinitionVersion.postgresql12 }}
{{- end -}}
{{- end -}}

{{/*
Define postgresql14 component definition name
*/}}
{{- define "postgresql.compDefPostgresql14" -}}
{{- if eq (len .Values.componentDefinitionVersion.postgresql14) 0 -}}
postgresql-14
{{- else -}}
{{ include "postgresql.componentDefNamePrefix" . }}{{ .Values.componentDefinitionVersion.postgresql14 }}
{{- end -}}
{{- end -}}

{{/*
Define postgresql15 component definition name
*/}}
{{- define "postgresql.compDefPostgresql15" -}}
{{- if eq (len .Values.componentDefinitionVersion.postgresql15) 0 -}}
postgresql-15
{{- else -}}
{{ include "postgresql.componentDefNamePrefix" . }}{{ .Values.componentDefinitionVersion.postgresql15 }}
{{- end -}}
{{- end -}}

{{/*
Define image
*/}}
{{- define "postgresql.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "postgresql.image150" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tags.major12.minor150 }}
{{- end }}

{{- define "postgresql.image080" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tags.major14.minor080 }}
{{- end }}

{{- define "postgresql.image070" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tags.major15.minor070 }}
{{- end }}

{{- define "pgbouncer.repository" -}}
{{ .Values.pgbouncer.image.registry | default (.Values.image.registry | default "docker.io") }}/{{ .Values.pgbouncer.image.repository }}
{{- end }}

{{- define "pgbouncer.image" -}}
{{ .Values.pgbouncer.image.registry | default (.Values.image.registry | default "docker.io") }}/{{ .Values.pgbouncer.image.repository }}:{{ .Values.pgbouncer.image.tag }}
{{- end }}

{{- define "metrics.image" -}}
{{ .Values.metrics.image.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.metrics.image.repository }}:{{ default .Values.metrics.image.tag }}
{{- end }}
