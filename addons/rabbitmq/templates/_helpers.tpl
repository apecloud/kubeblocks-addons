{{/*
Expand the name of the chart.
*/}}
{{- define "rabbitmq.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "rabbitmq.fullname" -}}
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
{{- define "rabbitmq.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rabbitmq.labels" -}}
helm.sh/chart: {{ include "rabbitmq.chart" . }}
{{ include "rabbitmq.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}


{{/*
Selector labels
*/}}
{{- define "rabbitmq.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rabbitmq.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
Return rabbitmq service port
*/}}
{{- define "rabbitmq.service.port" -}}
{{- .Values.primary.service.ports.rabbitmq -}}
{{- end -}}

{{/*
Get the password key.
*/}}
{{- define "rabbitmq.password" -}}
{{- if or (.Release.IsInstall) (not (lookup "apps.kubeblocks.io/v1alpha1" "ClusterDefinition" "" "rabbitmq")) -}}
{{ .Values.auth.password | default "$(RANDOM_PASSWD)"}}
{{- else -}}
{{ index (lookup "apps.kubeblocks.io/v1alpha1" "ClusterDefinition" "" "rabbitmq").spec.connectionCredential "password"}}
{{- end }}
{{- end }}

{{/*
Check if cluster version is enabled, if enabledClusterVersions is empty, return true,
otherwise, check if the cluster version is in the enabledClusterVersions list, if yes, return true,
else return false.
Parameters: cvName, values
*/}}
{{- define "rabbitmq.isClusterVersionEnabled" -}}
{{- $cvName := .cvName -}}
{{- $enabledClusterVersions := .values.enabledClusterVersions -}}
{{- if eq (len $enabledClusterVersions) 0 -}}
    {{- true -}}
{{- else -}}
    {{- range $enabledClusterVersions -}}
        {{- if eq $cvName . -}}
            {{- true -}}
        {{- end -}}
    {{- end -}}
{{- end -}}
{{- end -}}
