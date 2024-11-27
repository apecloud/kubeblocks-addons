{{/*
Expand the name of the chart.
*/}}
{{- define "pulsar-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pulsar-cluster.fullname" -}}
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
{{- define "pulsar-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pulsar-cluster.labels" -}}
helm.sh/chart: {{ include "pulsar-cluster.chart" . }}
{{ include "pulsar-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pulsar-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pulsar-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "clustername" -}}
{{ include "pulsar-cluster.fullname" .}}
{{- end}}

{{/*
Create the name of the service account to use
*/}}
{{- define "pulsar-cluster.serviceAccountName" -}}
{{- default (printf "kb-%s" (include "clustername" .)) .Values.serviceAccount.name }}
{{- end }}


{{/*
Pulsar broker FQDN
*/}}
{{- define "pulsar-cluster.brokerFQDN" -}}
{{- if eq .Values.version "3.0.2" }}
{{- include "kblib.clusterName" . }}-broker-bootstrap.{{ .Release.Namespace }}.svc{{ .Values.clusterDomain }}
{{- else }}
{{- include "kblib.clusterName" . }}-broker.{{ .Release.Namespace }}.svc{{ .Values.clusterDomain }}
{{- end }}
{{- end }}

{{/*
Pulsar ZooKeeper service ref
*/}}
{{- define "pulsar-zookeeper-ref"}}
{{- if .Values.serviceReference.enabled }}
serviceRefs:
- name: pulsarZookeeper
  namespace: {{ .Values.serviceReference.zookeeper.namespace | default .Release.Namespace }}
  {{- if .Values.serviceReference.zookeeper.clusterServiceSelector }}
  clusterServiceSelector:
    cluster: {{ .Values.serviceReference.zookeeper.clusterServiceSelector.cluster }}
    {{- if .Values.serviceReference.zookeeper.clusterServiceSelector.service}}
    service:
    {{- if .Values.serviceReference.zookeeper.clusterServiceSelector.service.component}}
      component: {{.Values.serviceReference.zookeeper.clusterServiceSelector.service.component}}
    {{- end}}
      service: client
    {{- if .Values.serviceReference.zookeeper.clusterServiceSelector.service.port}}
      port: {{.Values.serviceReference.zookeeper.clusterServiceSelector.service.port}}
    {{- end}}
    {{- end}}
    {{- if .Values.serviceReference.zookeeper.clusterServiceSelector.credential}}
    credential:
      component: {{.Values.serviceReference.zookeeper.clusterServiceSelector.credential.component}}
      name: {{.Values.serviceReference.zookeeper.clusterServiceSelector.credential.name}}
    {{- end}}
  {{- end}}
  {{- if .Values.serviceReference.zookeeper.serviceDescriptor }}
    serviceDescriptor: {{.Values.serviceReference.zookeeper.serviceDescriptor}}
  {{- end }}
  {{- end }}
{{- end}}
}}

{{/*
Define Pulsar cluster annotation keys for nodeport feature gate.
*/}}
{{- define "pulsar-cluster.brokerAddrFeatureGate" -}}
kubeblocks.io/enabled-pod-ordinal-svc: broker
{{- if .Values.nodePortEnabled }}
kubeblocks.io/enabled-node-port-svc: broker
kubeblocks.io/disabled-cluster-ip-svc: broker
{{- end }}
{{- end }}