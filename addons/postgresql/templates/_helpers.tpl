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
Common annotations
*/}}
{{- define "postgresql.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "postgresql.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "postgresql.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
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
Define postgresql cluster definition name
*/}}
{{- define "postgresql.clusterDefinition" -}}
postgresql
{{- end -}}

{{/*
Define postgresql component version name
*/}}
{{- define "postgresql.componentVersion" -}}
postgresql
{{- end -}}

{{/*
Define postgresql component definition name prefix
*/}}
{{- define "postgresql.componentDefNamePrefix" -}}
{{- printf "postgresql-" -}}
{{- end -}}

{{/*
Define postgresql component definition name prefix by major version
*/}}
{{- define "postgresql.componentDefNamePrefixByMajor" -}}
{{ printf "postgresql-%s-" .major }}
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
        {{- break -}}
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
    {{- break -}}
  {{- end -}}
{{- end -}}
{{- if $componentDef -}}
{{- printf "%s-%s" $componentDef $root.Chart.Version -}}
{{- else -}}
{{- fail (printf "componentDef not found for major: %s" $major) -}}
{{- end -}}
{{- end -}}

{{/*
Define component configuration template name by major version
*/}}
{{- define "postgresql.parameterTemplate" -}}
{{- $major := .major -}}
{{- $root := .root -}}
postgresql{{ $major }}-configuration-{{ $root.Chart.Version }}
{{- end -}}

{{/*
Define component config constraint name by major version
*/}}
{{- define "postgresql.parametersDefinition" -}}
{{- $major := .major -}}
{{- $root := .root -}}
postgresql{{ $major }}-pd-{{ $root.Chart.Version }}
{{- end -}}

{{/*
Define ParameterDrivenConfigRender name by major version
*/}}
{{- define "postgresql.pcr" -}}
{{- $major := .major -}}
{{- $root := .root -}}
postgresql{{ $major }}-pcr-{{ $root.Chart.Version }}
{{- end -}}

{{/*
Define component metrics configuration name by major version
*/}}
{{- define "postgresql.metricsConfiguration" -}}
postgresql{{ .major }}-custom-metrics
{{- end -}}

{{/*
Define postgresql scripts configMap template name
*/}}
{{- define "postgresql.scriptsTemplate" -}}
postgresql-scripts-{{ .Chart.Version }}
{{- end -}}

{{/*
Define postgresql patroni reload scripts template name
*/}}
{{- define "postgresql.patroniReloadScriptsTemplate" -}}
patroni-reload-scripts-{{ .Chart.Version }}
{{- end -}}

{{/*
Generate reloader scripts configmap
*/}}
{{- define "postgresql.extend.reload.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "reloader/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Define pgbouncer configuration template name
*/}}
{{- define "pgbouncer.configurationTemplate" -}}
pgbouncer-configuration-{{ .Chart.Version }}
{{- end -}}

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

{{- define "postgresql.dbctlImage" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.dbctl.repository }}:{{ .Values.image.dbctl.tag }}
{{- end }}

{{- define "postgresql.walgImage" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.walg.repository }}:{{ .Values.image.walg.tag }}
{{- end }}

{{- define "postgresql.initImage" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.init.repository }}:{{ .Values.image.init.tag }}
{{- end }}