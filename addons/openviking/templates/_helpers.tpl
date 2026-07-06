{{/*
Expand the name of the chart.
*/}}
{{- define "openviking.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "openviking.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "openviking.labels" -}}
helm.sh/chart: {{ include "openviking.chart" . }}
{{ include "openviking.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "openviking.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openviking.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
API version annotation - matches the kubeblocks CRD api version this addon targets.
*/}}
{{- define "openviking.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Common annotations
*/}}
{{- define "openviking.annotations" -}}
{{ include "openviking.apiVersion" . }}
{{- end }}

{{/*
Define openviking 0.X component definition name.
*/}}
{{- define "openviking.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.major0) 0 -}}
openviking-0-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.major0 -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Regular expression matching all openviking 0.X component definitions.
Used by ComponentVersion.compatibilityRules.
*/}}
{{- define "openviking.cmpdRegexpPattern" -}}
^openviking-0.*
{{- end -}}

{{/*
Config template name (a Kubernetes ConfigMap created from config-template.yaml).
*/}}
{{- define "openviking.configTemplate" -}}
openviking-config-template-{{ .Chart.Version }}
{{- end }}

{{/*
ParametersDefinition name. A single PD covers ov.conf for all openviking 0.X
chart versions, since the parameter surface is stable.
*/}}
{{- define "openviking.paramsDefName" -}}
openviking-pd
{{- end }}

{{/*
Full image reference for the OpenViking container image.
*/}}
{{- define "openviking.repository" -}}
{{ .Values.image.registry | default "ghcr.io" }}/{{ .Values.image.repository | default "volcengine/openviking" }}
{{- end }}
