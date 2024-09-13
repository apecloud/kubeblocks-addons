{{/*
Expand the name of the chart.
*/}}
{{- define "risingwave.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "risingwave.fullname" -}}
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
{{- define "risingwave.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "risingwave.selectorLabels" -}}
app.kubernetes.io/name: {{ include "risingwave.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "risingwave.labels" -}}
helm.sh/chart: {{ include "risingwave.chart" . }}
{{ include "risingwave.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Default config template.
*/}}
{{- define "risingwave.conftpl.default" }}
- name: risingwave-configuration
  templateRef: {{ include "risingwave.name" . }}-conf-tpl
  namespace: {{ .Release.Namespace }}
  volumeName: risingwave-configuration
{{- end }}

{{/*
Volume mount for default config template.
*/}}
{{- define "risingwave.volumeMount.conftpl.default" }}
- name: risingwave-configuration
  mountPath: /risingwave/config
{{- end }}

{{/*
Liveness probe.
*/}}
{{- define "risingwave.probe.liveness" }}
livenessProbe:
  failureThreshold: 3
  tcpSocket:
    port: svc
  initialDelaySeconds: 5
  periodSeconds: 10
  successThreshold: 1
  timeoutSeconds: 30
{{- end }}

{{/*
Readiness probe.
*/}}
{{- define "risingwave.probe.readiness" }}
readinessProbe:
  failureThreshold: 3
  tcpSocket:
    port: svc
  initialDelaySeconds: 5
  periodSeconds: 10
  successThreshold: 1
  timeoutSeconds: 30
{{- end }}

{{/*
Default security context.
*/}}
{{- define "risingwave.securityContext" }}
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  privileged: false
{{- end }}

{{/*
Connector service vars.
*/}}
{{- define "risingwave.vars.connector" }}
- name: CONNECTOR_SVC
  valueFrom:
    serviceVarRef:
      compDef: risingwave-connector
      optional: false
      host: Required
{{- end }}

{{/*
Meta service vars.
*/}}
{{- define "risingwave.vars.meta" }}
- name: META_SVC
  valueFrom:
    serviceVarRef:
      compDef: risingwave-meta
      optional: false
      host: Required
{{- end }}