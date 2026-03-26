{{/*
Expand the name of the chart.
*/}}
{{- define "dolt.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "dolt.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dolt.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "dolt.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "dolt.labels" -}}
helm.sh/chart: {{ include "dolt.chart" . }}
{{ include "dolt.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common annotations.
*/}}
{{- define "dolt.annotations" -}}
{{ include "dolt.apiVersion" . }}
{{- end }}

{{/*
API version annotation.
*/}}
{{- define "dolt.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
ComponentDefinition name (replication / primary-standby).
*/}}
{{- define "dolt.cmpdName" -}}
dolt-replication
{{- end -}}

{{/*
ComponentDefinition regexp for replication cmpd.
*/}}
{{- define "dolt.cmpdRegexpPattern" -}}
^dolt-replication$
{{- end -}}

{{/*
Config template name.
*/}}
{{- define "dolt.configTemplate" -}}
dolt-config-template-{{ .Chart.Version }}
{{- end }}

{{/*
Script template name.
*/}}
{{- define "dolt.scriptTemplate" -}}
dolt-script-template-{{ .Chart.Version }}
{{- end }}

{{/*
Standalone ComponentDefinition name.
*/}}
{{- define "dolt.standaloneCmpdName" -}}
dolt-standalone
{{- end -}}

{{/*
Standalone ComponentDefinition regexp.
*/}}
{{- define "dolt.standaloneCmpdRegexpPattern" -}}
^dolt-standalone$
{{- end -}}

{{/*
Standalone config template name.
*/}}
{{- define "dolt.standaloneConfigTemplate" -}}
dolt-standalone-config-template-{{ .Chart.Version }}
{{- end }}

{{/*
Generate scripts configmap.
*/}}
{{- define "dolt.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}
