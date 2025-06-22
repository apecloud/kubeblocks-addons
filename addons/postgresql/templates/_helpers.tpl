{{/*
Expand the name of the chart.
*/}}
{{- define "postgresql.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "postgresql.fullname" -}}
{{- $name := .Chart.Name }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
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
Define image
*/}}
{{- define "postgresql.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "postgresql.pgbouncerImage" -}}
{{ .Values.pgbouncer.image.registry | default (.Values.image.registry | default "docker.io") }}/{{ .Values.pgbouncer.image.repository }}:{{ .Values.pgbouncer.image.tag }}
{{- end }}

{{- define "postgresql.metricsImage" -}}
{{ .Values.metrics.image.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.metrics.image.repository }}:{{ default .Values.metrics.image.tag }}
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
Get PostgreSQL image address by major and minor version
Parameters: major (string), minor (string), root context
Usage: {{ include "postgresql.imageByVersion" (dict "major" "14" "minor" "14.8.0" "root" .) }}
*/}}
{{- define "postgresql.imageByVersion" -}}
{{- $major := .major -}}
{{- $minor := .minor -}}
{{- $root := .root -}}
{{- $tag := "" -}}
{{- range $root.Values.versions -}}
  {{- if eq .major $major -}}
    {{- range .minors -}}
      {{- if eq .version $minor -}}
        {{- $tag = .tag -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if $tag -}}
{{- printf "%s/%s:%s" ($root.Values.image.registry | default "docker.io") $root.Values.image.repository $tag -}}
{{- else -}}
{{- fail (printf "image tag not found for major: %s, minor: %s" $major $minor) -}}
{{- end -}}
{{- end -}}

{{/*
Get PostgreSQL image pull policy
Parameters: root context
Usage: {{ include "postgresql.imagePullPolicy" . }}
*/}}
{{- define "postgresql.imagePullPolicy" -}}
{{- default "IfNotPresent" .Values.image.pullPolicy -}}
{{- end -}}

{{/*
Get PostgreSQL componentDef by major version
Parameters: major (string), root context
Usage: {{ include "postgresql.componentDefByMajor" (dict "major" "14" "root" .) }}
*/}}
{{- define "postgresql.componentDefByMajor" -}}
{{- $major := .major -}}
{{- $root := .root -}}
{{- $componentDef := "" -}}
{{- range $root.Values.versions -}}
  {{- if eq .major $major -}}
    {{- $componentDef = .componentDef -}}
  {{- end -}}
{{- end -}}
{{- $componentDef -}}
{{- end -}}

{{/*
Get PostgreSQL action image by major version
Parameters: major (string), root context
Usage: {{ include "postgresql.actionImageByMajor" (dict "major" "14" "root" .) }}
*/}}
{{- define "postgresql.actionImageByMajor" -}}
{{- $major := .major -}}
{{- $root := .root -}}
{{- $actionImageTag := "" -}}
{{- range $root.Values.versions -}}
  {{- if eq .major $major -}}
    {{- $actionImageTag = .actionImageTag -}}
  {{- end -}}
{{- end -}}
{{- printf "%s/%s:%s" ($root.Values.image.registry | default "docker.io") $root.Values.image.repository $actionImageTag -}}
{{- end -}}