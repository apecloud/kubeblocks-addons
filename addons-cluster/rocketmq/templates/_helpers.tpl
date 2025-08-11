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
Create extra envs annotations
*/}}
{{- define "rocketmq-cluster.annotations.extra-envs" -}}
"kubeblocks.io/extra-env": {{ include "rocketmq-cluster.extra-envs" . | nospace  | quote }}
{{- end -}}

{{/*
Create extra env
*/}}
{{- define "rocketmq-cluster.extra-envs" -}}
{
"ENABLE_ACL": "{{ .Values.broker.enableAcl }}",
"ENABLE_DLEDGER": "{{ .Values.broker.enableDledger }}"
}
{{- end -}}

{{/*
Define rocketmq-exporter resources
*/}}
{{- define "rocketmq-exporter.resources" }}
{{- $requestCPU := (float64 .Values.monitor.request.cpu) }}
{{- $requestMemory := (float64 .Values.monitor.request.memory) }}
{{- $limitCPU := (float64 .Values.monitor.limit.cpu) }}
{{- $limitMemory := (float64 .Values.monitor.limit.memory) }}
resources:
  limits:
    cpu: {{ $limitCPU | quote }}
    memory: {{ print $limitMemory "Gi" | quote }}
  requests:
    cpu: {{ $requestCPU | quote }}
    memory: {{ print $requestMemory "Gi" | quote }}
{{- end }}

{{/*
Define rocketmq-dashboard resources
*/}}
{{- define "rocketmq-dashboard.resources" }}
{{- $requestCPU := (float64 .Values.dashboard.request.cpu) }}
{{- $requestMemory := (float64 .Values.dashboard.request.memory) }}
{{- $limitCPU := (float64 .Values.dashboard.limit.cpu) }}
{{- $limitMemory := (float64 .Values.dashboard.limit.memory) }}
resources:
  limits:
    cpu: {{ $limitCPU | quote }}
    memory: {{ print $limitMemory "Gi" | quote }}
  requests:
    cpu: {{ $requestCPU | quote }}
    memory: {{ print $requestMemory "Gi" | quote }}
{{- end }}