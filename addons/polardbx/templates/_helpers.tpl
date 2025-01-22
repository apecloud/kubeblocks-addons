{{/*
Expand the name of the chart.
*/}}
{{- define "polardbx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "polardbx.fullname" -}}
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
{{- define "polardbx.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "polardbx.labels" -}}
helm.sh/chart: {{ include "polardbx.chart" . }}
{{ include "polardbx.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "polardbx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "polardbx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "polardbx.annotations" -}}
helm.sh/resource-policy: keep
{{ include "polardbx.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "polardbx.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define polardbx scripts configMap template name
*/}}
{{- define "polardbx.scriptsTemplate" -}}
polardbx-scripts-template
{{- end -}}

{{/*
Define polardbx cdc component definition name
*/}}
{{- define "polardbx-cdc.cmpdName" -}}
polardbx-cdc-{{ .Chart.Version }}
{{- end -}}

{{/*
Define polardbx cdc component version name
*/}}
{{- define "polardbx-cdc.cmpvName" -}}
polardbx-cdc
{{- end -}}

{{/*
Define polardbx cdc component definition regex pattern
*/}}
{{- define "polardbx-cdc.cmpdRegexPattern" -}}
^polardbx-cdc-
{{- end -}}

{{/*
Define polardbx cn component definition name
*/}}
{{- define "polardbx-cn.cmpdName" -}}
polardbx-cn-{{ .Chart.Version }}
{{- end -}}

{{/*
Define polardbx cn component version name
*/}}
{{- define "polardbx-cn.cmpvName" -}}
polardbx-cn
{{- end -}}

{{/*
Define polardbx cn component definition regex pattern
*/}}
{{- define "polardbx-cn.cmpdRegexPattern" -}}
^polardbx-cn-
{{- end -}}

{{/*
Define polardbx dn component definition name
*/}}
{{- define "polardbx-dn.cmpdName" -}}
polardbx-dn-{{ .Chart.Version }}
{{- end -}}

{{/*
Define polardbx dn component version name
*/}}
{{- define "polardbx-dn.cmpvName" -}}
polardbx-dn
{{- end -}}

{{/*
Define polardbx dn component definition regex pattern
*/}}
{{- define "polardbx-dn.cmpdRegexPattern" -}}
^polardbx-dn-
{{- end -}}

{{/*
Define polardbx gms component definition name
*/}}
{{- define "polardbx-gms.cmpdName" -}}
polardbx-gms-{{ .Chart.Version }}
{{- end -}}

{{/*
Define polardbx gms component version name
*/}}
{{- define "polardbx-gms.cmpvName" -}}
polardbx-gms
{{- end -}}

{{/*
Define polardbx gms component definition regex pattern
*/}}
{{- define "polardbx-gms.cmpdRegexPattern" -}}
^polardbx-gms-
{{- end -}}
