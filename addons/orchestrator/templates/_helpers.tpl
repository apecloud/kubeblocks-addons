{{/*
Expand the name of the chart.
*/}}
{{- define "orchestrator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "orchestrator.fullname" -}}
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
{{- define "orchestrator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "orchestrator.labels" -}}
helm.sh/chart: {{ include "orchestrator.chart" . }}
{{ include "orchestrator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "orchestrator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "orchestrator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "orchestrator.annotations" -}}
{{ include "orchestrator.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "orchestrator.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "orchestrator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "orchestrator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Define mysql component definition name
*/}}
{{- define "orchestrator.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
orchestrator
{{- else -}}
{{- printf "orchestrator-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}


{{/*
Generate configmap
*/}}
{{- define "orchestrator.extend.configs" -}}
{{- range $path, $_ :=  $.Files.Glob "configs/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}


{{/*
Generate scripts
*/}}
{{- define "orchestrator.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}


{{- define "orchestrator.cmpd.spec.common" -}}
provider: kubeblocks
description: orchestrator is a MySQL high availability and replication management tool
serviceKind: orchestrator
serviceVersion: 3.2.6
updateStrategy: BestEffortParallel

configs:
  - name: orchestrator-config
    templateRef: {{ include "orchestrator.componentDefName" . }}-config
    namespace: {{ .Release.Namespace }}
    volumeName: configs

scripts:
  - name: orc-scripts
    templateRef: {{ include "orchestrator.componentDefName" . }}-scripts
    namespace: {{ .Release.Namespace }}
    volumeName: scripts
    defaultMode: 0555

{{- end }}


{{- define "orchestrator.cmpd.spec.runtime.common" -}}
command:
  - bash
  - -c
  - |
    /scripts/startup.sh
volumeMounts:
  - name: configs
    mountPath: /configs
  - name: scripts
    mountPath: /scripts
  - mountPath:  {{ .Values.config.dataDir }}
    name: data
ports:
  - containerPort: 3000
    name: orc-http
  - containerPort: 10008
    name: raft
readinessProbe:
  failureThreshold: 5
  httpGet:
    path: /api/health
    port: 3000
    scheme: HTTP
  periodSeconds: 10
  successThreshold: 1
  timeoutSeconds: 3
{{- end }}
