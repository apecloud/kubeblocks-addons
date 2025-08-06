{{/*
Expand the name of the chart.
*/}}
{{- define "rocketmq.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "rocketmq.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "rocketmq.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Common annotations
*/}}
{{- define "rocketmq.annotations" -}}
helm.sh/resource-policy: keep
{{ include "rocketmq.apiVersion" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "rocketmq.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rocketmq.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rocketmq.labels" -}}
helm.sh/chart: {{ include "rocketmq.chart" . }}
{{ include "rocketmq.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Define rocketmq broker component definition name prefix
*/}}
{{- define "rocketmq-broker.componentDefNamePrefix" -}}
{{- printf "rocketmq-broker-" -}}
{{- end -}}

{{/*
Define rocketmq nameserver component definition name prefix
*/}}
{{- define "rocketmq-namesrv.componentDefNamePrefix" -}}
{{- printf "rocketmq-namesrv-" -}}
{{- end -}}

{{/*
Define rocketmq broker 4.x component definition name
*/}}
{{- define "rocketmq.compDefRocketMQBroker4" -}}
{{- if eq (len .Values.componentDefinitionVersion.rocketMQ4) 0 -}}
{{ include "rocketmq.name" . }}-broker-4-{{ .Chart.Version }}
{{- else -}}
{{ include "rocketmq-broker.componentDefNamePrefix" . }}{{ .Values.componentDefinitionVersion.rocketMQ4 }}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define rocketmq nameserver 4.x component definition name
*/}}
{{- define "rocketmq.compDefRocketMQNameSrv4" -}}
{{- if eq (len .Values.componentDefinitionVersion.rocketMQ4) 0 -}}
{{ include "rocketmq.name" . }}-namesrv-4-{{ .Chart.Version }}
{{- else -}}
{{ include "rocketmq-namesrv.componentDefNamePrefix" . }}{{ .Values.componentDefinitionVersion.rocketMQ4 }}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define rocketmq exporter component definition name
*/}}
{{- define "rocketmq.compDefRocketMQExporter" -}}
{{ include "rocketmq.name" . }}-exporter-{{ .Chart.Version }}
{{- end -}}

{{/*
Define rocketmq dashboard component definition name
*/}}
{{- define "rocketmq.compDefRocketMQDashboard" -}}
{{ include "rocketmq.name" . }}-dashboard-{{ .Chart.Version }}
{{- end -}}

{{/*
Define rocketmq broker 4 component configuration template name
*/}}
{{- define "rocketmq-broker4.configurationTemplate" -}}
rocketmq-broker4-configuration
{{- end -}}

{{/*
Define rocketmq nameserver 4 component configuration template name
*/}}
{{- define "rocketmq-namesrv4.configurationTemplate" -}}
rocketmq-namesrv4-configuration
{{- end -}}

{{/*
Define rocketmq jmx-exporter configuration template name
*/}}
{{- define "rocketmq.jxm-exporter.configurationTemplate" -}}
rocketmq-jmx-configuration-tpl
{{- end -}}

{{/*
Define rocketmq broker 4 component config constraint name
*/}}
{{- define "rocketmq-broker4.pdName" -}}
rocketmq-broker4-pd
{{- end -}}

{{- define "rocketmq-broker4.prcName" -}}
rocketmq-broker4-pcr
{{- end -}}

{{/*
Define rocketmq broker 4 scripts configMap template name
*/}}
{{- define "rocketmq-broker4.scriptsTemplate" -}}
rocketmq-broker4-scripts
{{- end -}}

{{/*
Define rocketmq nameserver 4 scripts configMap template name
*/}}
{{- define "rocketmq-namesrv4.scriptsTemplate" -}}
rocketmq-namesrv4-scripts
{{- end -}}

{{/*
Define rocketmq exporter scripts configMap template name
*/}}
{{- define "rocketmq-exporter.scriptsTemplate" -}}
rocketmq-exporter-scripts
{{- end -}}

{{/*
Define rocketmq dashboard scripts configMap template name
*/}}
{{- define "rocketmq-dashboard.scriptsTemplate" -}}
rocketmq-dashboard-scripts
{{- end -}}

{{/*
Generate scripts configmap
*/}}
{{- define "rocketmq.extend.reload.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "reloader/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Define rocketmq scripts configMap template name
*/}}
{{- define "rocketmq.reloader.scripts" -}}
rocketmq-reload-tools-script
{{- end -}}
