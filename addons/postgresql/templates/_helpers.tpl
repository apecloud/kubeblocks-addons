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
Check if cluster version is enabled, if enabledClusterVersions is empty, return true,
otherwise, check if the cluster version is in the enabledClusterVersions list, if yes, return true,
else return false.
Parameters: cvName, values
*/}}
{{- define "postgresql.isClusterVersionEnabled" -}}
{{- $cvName := .cvName -}}
{{- $enabledClusterVersions := .values.enabledClusterVersions -}}
{{- if eq (len $enabledClusterVersions) 0 -}}
    {{- true -}}
{{- else -}}
    {{- range $enabledClusterVersions -}}
        {{- if eq $cvName . -}}
            {{- true -}}
        {{- end -}}
    {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Define postgresql component defintion name prefix
*/}}
{{- define "postgresql.componentDefNamePrefix" -}}
{{- printf "postgresql-" -}}
{{- end -}}

{{/*
Define postgresql12 component defintion name
*/}}
{{- define "postgresql.compDefPostgresql12" -}}
{{- if eq (len .Values.componentDefinitionVersion.postgresql12) 0 -}}
postgresql-12
{{- else -}}
{{ include "postgresql.componentDefNamePrefix" . }}{{ .Values.componentDefinitionVersion.postgresql12 }}
{{- end -}}
{{- end -}}

{{/*
Define postgresql14 component defintion name
*/}}
{{- define "postgresql.compDefPostgresql14" -}}
{{- if eq (len .Values.componentDefinitionVersion.postgresql14) 0 -}}
postgresql-14
{{- else -}}
{{ include "postgresql.componentDefNamePrefix" . }}{{ .Values.componentDefinitionVersion.postgresql14 }}
{{- end -}}
{{- end -}}

{{/*
Define postgresql15 component defintion name
*/}}
{{- define "postgresql.compDefPostgresql15" -}}
{{- if eq (len .Values.componentDefinitionVersion.postgresql15) 0 -}}
postgresql-15
{{- else -}}
{{ include "postgresql.componentDefNamePrefix" . }}{{ .Values.componentDefinitionVersion.postgresql15 }}
{{- end -}}
{{- end -}}