{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "doltdb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "doltdb.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "doltdb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "doltdb.labels" -}}
helm.sh/chart: {{ include "doltdb.chart" . }}
{{ include "doltdb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "doltdb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "doltdb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations.
*/}}
{{- define "doltdb.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "doltdb.apiVersion" . }}
{{- end }}

{{/*
API version annotation.
*/}}
{{- define "doltdb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define DoltDB component definition name.
*/}}
{{- define "doltdb.cmpdName" -}}
doltdb-{{ .Chart.Version }}
{{- end -}}

{{/*
Define DoltDB component definition regular expression name prefix.
*/}}
{{- define "doltdb.cmpdRegexpPattern" -}}
^doltdb-[0-9]
{{- end -}}

{{/*
Define DoltDB replication component definition name.
*/}}
{{- define "doltdb.replicationCmpdName" -}}
doltdb-replication-{{ .Chart.Version }}
{{- end -}}

{{/*
Define DoltDB replication component definition regular expression name prefix.
*/}}
{{- define "doltdb.replicationCmpdRegexpPattern" -}}
^doltdb-replication-
{{- end -}}

{{/*
Define DoltDB configuration template name.
*/}}
{{- define "doltdb.configTemplate" -}}
doltdb-config-template-{{ .Chart.Version }}
{{- end -}}

{{/*
Define DoltDB scripts template name.
*/}}
{{- define "doltdb.scriptsTemplate" -}}
doltdb-scripts-template-{{ .Chart.Version }}
{{- end -}}

{{/*
Define DoltDB backup ActionSet names.
*/}}
{{- define "doltdb.backupActionSet" -}}
doltdb-backup
{{- end -}}

{{/*
Define DoltDB BackupPolicyTemplate name.
*/}}
{{- define "doltdb.backupPolicyTemplate" -}}
doltdb-backup-policy-template
{{- end -}}

{{/*
Define DoltDB replication BackupPolicyTemplate name.
*/}}
{{- define "doltdb.replicationBackupPolicyTemplate" -}}
doltdb-replication-backup-policy-template
{{- end -}}

{{/*
Get DoltDB default image.
*/}}
{{- define "doltdb.defaultImage" -}}
{{- $tag := "" -}}
{{- range .Values.versions -}}
  {{- if .isDefault -}}
    {{- $tag = .tag -}}
    {{- break -}}
  {{- end -}}
{{- end -}}
{{- if not $tag -}}
  {{- $tag = (index .Values.versions 0).tag -}}
{{- end -}}
{{- printf "%s/%s:%s" (.Values.image.registry | default "docker.io") .Values.image.repository $tag -}}
{{- end -}}

{{/*
Get DoltDB default service version.
*/}}
{{- define "doltdb.defaultServiceVersion" -}}
{{- $defaultVersion := "" -}}
{{- range .Values.versions -}}
  {{- if .isDefault -}}
    {{- $defaultVersion = .serviceVersion -}}
    {{- break -}}
  {{- end -}}
{{- end -}}
{{- if not $defaultVersion -}}
  {{- $defaultVersion = (index .Values.versions 0).serviceVersion -}}
{{- end -}}
{{- $defaultVersion -}}
{{- end -}}
