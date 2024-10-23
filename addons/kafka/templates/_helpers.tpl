{{/*
Expand the name of the chart.
*/}}
{{- define "kafka.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kafka.fullname" -}}
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
{{- define "kafka.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kafka.labels" -}}
helm.sh/chart: {{ include "kafka.chart" . }}
{{ include "kafka.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kafka.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kafka.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "kafka.annotations" -}}
helm.sh/resource-policy: keep
{{- end }}

{{/*
Define kafka.combine component definition name
*/}}
{{- define "kafka-combine.componentDefName" -}}
kafka-combine-{{ .Chart.Version }}
{{- end -}}

{{/*
Define kafka.combine component definition regex pattern
*/}}
{{- define "kafka-combine.cmpdRegexpPattern" -}}
^kafka-combine-
{{- end -}}

{{/*
Define kafka-exporter component definition name
*/}}
{{- define "kafka-exporter.componentDefName" -}}
kafka-exporter-{{ .Chart.Version }}
{{- end -}}

{{/*
Define kafka-exporter component definition regex pattern
*/}}
{{- define "kafka-exporter.cmpdRegexpPattern" -}}
^kafka-exporter-
{{- end -}}

{{/*
Define kafka-controller component definition name
*/}}
{{- define "kafka-controller.componentDefName" -}}
kafka-controller-{{ .Chart.Version }}
{{- end -}}

{{/*
Define kafka-controller component definition regex pattern
*/}}
{{- define "kafka-controller.cmpdRegexpPattern" -}}
^kafka-controller-
{{- end -}}

{{/*
Define kafka-broker component definition name
*/}}
{{- define "kafka-broker.componentDefName" -}}
kafka-broker-{{ .Chart.Version }}
{{- end -}}

{{/*
Define kafka-broker component definition regex pattern
*/}}
{{- define "kafka-broker.cmpdRegexpPattern" -}}
^kafka-broker-
{{- end -}}

{{/*
Define kafka config constraint name
*/}}
{{- define "kafka.configConstraintName" -}}
kafka-config-constraints
{{- end -}}

{{/*
Define kafka configuration tpl name
*/}}
{{- define "kafka.configurationTplName" -}}
kafka-configuration-tpl
{{- end -}}

{{/*
Define kafka jmx configuration tpl name
*/}}
{{- define "kafka.jmxConfigurationTplName" -}}
kafka-jmx-configuration-tpl
{{- end -}}

{{/*
Define kafka server scripts tpl name
*/}}
{{- define "kafka.serverScriptsTplName" -}}
kafka-server-scripts-tpl
{{- end -}}

{{/*
Define kafka tools scripts tpl name
*/}}
{{- define "kafka.toolsScriptsTplName" -}}
kafka-scripts-tools-tpl
{{- end -}}

{{/*
Define kafka default client system account secret name
*/}}
{{- define "kafka.defaultClientSystemAccountSecretName" -}}
kafka-client-secret
{{- end -}}

{{/*
Define kafka default superuser system account secret name
*/}}
{{- define "kafka.defaultSpuerUserSystemAccountSecretName" -}}
kafka-superusers-secret
{{- end -}}
