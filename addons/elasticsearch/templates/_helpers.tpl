{{/*
Expand the name of the chart.
*/}}
{{- define "elasticsearch.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "elasticsearch.fullname" -}}
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
{{- define "elasticsearch.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "elasticsearch.labels" -}}
helm.sh/chart: {{ include "elasticsearch.chart" . }}
{{ include "elasticsearch.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "elasticsearch.selectorLabels" -}}
app.kubernetes.io/name: {{ include "elasticsearch.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "elasticsearch.annotations" -}}
helm.sh/resource-policy: keep
{{ include "elasticsearch.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "elasticsearch.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define elasticsearch component definition regex pattern
*/}}
{{- define "elasticsearch.cmpdRegexPattern" -}}
^elasticsearch-
{{- end -}}

{{/*
Define elasticsearch v7.X component definition name
*/}}
{{- define "elasticsearch7.cmpdName" -}}
elasticsearch-7-{{ .Chart.Version }}
{{- end -}}

{{/*
Define elasticsearch v7.X component definition regex pattern
*/}}
{{- define "elasticsearch7.cmpdRegexPattern" -}}
^elasticsearch-7-
{{- end -}}

{{/*
Define elasticsearch v8.X component definition name
*/}}
{{- define "elasticsearch8.cmpdName" -}}
elasticsearch-8-{{ .Chart.Version }}
{{- end -}}

{{/*
Define elasticsearch v8.X component definition regex pattern
*/}}
{{- define "elasticsearch8.cmpdRegexPattern" -}}
^elasticsearch-8-
{{- end -}}

{{/*
Define elasticsearch scripts tpl name
*/}}
{{- define "elasticsearch.scriptsTplName" -}}
elasticsearch-scripts-tpl
{{- end -}}

{{/*
Define elasticsearch v7.X config tpl name
*/}}
{{- define "elasticsearch7.configTplName" -}}
elasticsearch-7-config-tpl
{{- end -}}

{{/*
Define elasticsearch v8.X config tpl name
*/}}
{{- define "elasticsearch8.configTplName" -}}
elasticsearch-8-config-tpl
{{- end -}}

{{- define "elasticsearch-8.1.3.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:8.1.3
{{- end }}

{{- define "elasticsearch-8.8.2.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:8.8.2
{{- end }}

{{- define "elasticsearch-8.9.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:8.9.1
{{- end }}

{{- define "elasticsearch-8.15.5.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:8.15.5
{{- end }}

{{- define "elasticsearch-7.10.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:7.10.1
{{- end }}

{{- define "elasticsearch-7.7.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:7.7.1
{{- end }}

{{- define "elasticsearch-7.8.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:7.8.1
{{- end }}

{{- define "elasticsearch-6.8.23.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:6.8.23
{{- end }}

{{- define "elasticsearch-exporter.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.exporter.repository }}:{{ .Values.image.exporter.tag | default "latest" }}
{{- end }}

{{/*
Define elasticsearch v7.X parameter config renderer name
*/}}
{{- define "elasticsearch7.pcrName" -}}
elasticsearch7-pcr
{{- end }}

{{/*
Define elasticsearch v8.X parameter config renderer name
*/}}
{{- define "elasticsearch8.pcrName" -}}
elasticsearch8-pcr
{{- end }}

{{/*
Define kibana v8.X component definition name
*/}}
{{- define "kibana8.cmpdName" -}}
kibana-8-{{ .Chart.Version }}
{{- end -}}

{{/*
Define kibana v8.X component definition regex pattern
*/}}
{{- define "kibana8.cmpdRegexPattern" -}}
^kibana-8-
{{- end -}}

{{/*
Define kibana component definition regex pattern
*/}}
{{- define "kibana.cmpdRegexPattern" -}}
^kibana-
{{- end -}}

{{/*
Define kibana v7.X component definition name
*/}}
{{- define "kibana7.cmpdName" -}}
kibana-7-{{ .Chart.Version }}
{{- end -}}

{{/*
Define kibana v7.X component definition regex pattern
*/}}
{{- define "kibana7.cmpdRegexPattern" -}}
^kibana-7-
{{- end -}}

{{/*
Define kibana config tpl name
*/}}
{{- define "kibana.configTplName" -}}
kibana-config-tpl
{{- end -}}

{{- define "kibana-6.8.23.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:6.8.23
{{- end }}

{{- define "kibana-7.7.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:7.7.1
{{- end }}

{{- define "kibana-7.8.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:7.8.1
{{- end }}

{{- define "kibana-7.10.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:7.10.1
{{- end }}

{{- define "kibana-8.1.3.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:8.1.3
{{- end }}

{{- define "kibana-8.8.2.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:8.8.2
{{- end }}

{{- define "kibana-8.15.5.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:8.15.5
{{- end }}

{{- define "kibana-8.9.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:8.9.1
{{- end }}

{{- define "elasticsearch-agent.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.agent.repository }}:0.1.0
{{- end }}