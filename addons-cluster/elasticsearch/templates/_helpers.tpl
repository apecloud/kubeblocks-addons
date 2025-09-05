{{/*
Expand the name of the chart.
*/}}
{{- define "elasticsearch-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "elasticsearch-cluster.fullname" -}}
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
{{- define "elasticsearch-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "elasticsearch-cluster.labels" -}}
helm.sh/chart: {{ include "elasticsearch-cluster.chart" . }}
{{ include "elasticsearch-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "elasticsearch-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "elasticsearch-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "clustername" -}}
{{ include "elasticsearch-cluster.fullname" .}}
{{- end}}

{{- define "elasticsearch-cluster.replicaCount" }}
{{- if eq .Values.mode "single-node" }}
replicas: 1
{{- else if eq .Values.mode "multi-node" }}
replicas: {{ max .Values.replicas 3 }}
{{- end }}
{{- end }}

{{- define "elasticsearch.version" }}
{{- if .Values.version }}
{{- trimPrefix "elasticsearch-" .Values.version }}
{{- else }}
{{- .Chart.AppVersion }}
{{- end }}
{{- end }}

{{- define "elasticsearch.majorVersion" }}
{{- $version := semver (include "elasticsearch.version" .) }}
{{- printf "%d" $version.Major }}
{{- end }}

{{- define "elasticsearch-cluster.schedulingPolicy" }}
schedulingPolicy:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/instance: {{ include "kblib.clusterName" . }}
              apps.kubeblocks.io/component-name: elasticsearch
          topologyKey: kubernetes.io/hostname
        weight: 100
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/instance: {{ include "kblib.clusterName" . }}
            apps.kubeblocks.io/component-name: elasticsearch
        topologyKey: kubernetes.io/hostname
{{- end -}}

{{- define "tlsSecretName" -}}
{{- if .Values.tls.secretName -}}
{{- .Values.tls.secretName -}}
{{- else -}}
{{- include "kblib.clusterName" . -}}-tls-secret
{{- end -}}
{{- end -}}

{{- define "elasticAccountSecretname" -}}
{{- if .Values.tls.elasticAccountSecretName -}}
{{- .Values.tls.elasticAccountSecretName -}}
{{- else -}}
{{- include "kblib.clusterName" . -}}-account-elastic
{{- end -}}
{{- end -}}

{{- define "kibanaAccountSecretname" -}}
{{- if .Values.tls.kibanaAccountSecretName -}}
{{- .Values.tls.kibanaAccountSecretName -}}
{{- else -}}
{{- include "kblib.clusterName" . -}}-account-kibana-system
{{- end -}}
{{- end -}}


{{- define "elasticsearch-cluster.tls" }}
tls: {{ .Values.tls.enabled }}
{{- if .Values.tls.enabled }}
issuer:
  name: {{ .Values.tls.issuer }}
{{- if eq .Values.tls.issuer "UserProvided" }}
  secretRef:
    name: {{ include "tlsSecretName" . }}
    namespace: {{ .Release.Namespace }}
    ca: ca.crt
    cert: tls.crt
    key: tls.key
{{- end }}
{{- end }}
{{- end }}

{{- define "elasticsearch-cluster.accounts" }}
{{- if .Values.tls.enabled }}
systemAccounts:
- name: elastic
  secretRef:
    name: {{ include "elasticAccountSecretname" .}}
    namespace: {{ .Release.Namespace }}
- name: kibana_system
  secretRef:
    name: {{ include "kibanaAccountSecretname" .}}
    namespace: {{ .Release.Namespace }}
{{- end }}
{{- end }}
