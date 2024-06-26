{{/*
Expand the name of the chart.
*/}}
{{- define "oceanbase.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "oceanbase.fullname" -}}
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
{{- define "oceanbase.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "oceanbase.labels" -}}
helm.sh/chart: {{ include "oceanbase.chart" . }}
{{ include "oceanbase.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "oceanbase.selectorLabels" -}}
app.kubernetes.io/name: {{ include "oceanbase.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "oceanbase.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "oceanbase.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Create extra env
*/}}
{{- define "oceanbase-cluster.extra-envs" }}
{
{{- if .Values.tenant }}
"TENANT_NAME": "{{ .Values.tenant.name }}",
"TENANT_CPU": "{{ min (sub .Values.cpu 1) .Values.tenant.max_cpu }}",
"TENANT_MEMORY": "{{ print (min (sub .Values.memory  2) .Values.tenant.memory_size) "G" }}",
"TENANT_DISK": "{{ print (.Values.tenant.log_disk_size | default 5) "G" }}",
{{- end }}
"ZONE_COUNT": "{{ .Values.zoneCount | default "1" }}",
"OB_CLUSTERS_COUNT": "{{ .Values.obClusters | default "1" }}",
"OB_DEBUG": "{{ .Values.debug | default "false" }}"
}
{{- end }}


{{- define "oceanbase-release.name" }}
{{- print "ob-ce" }}
{{- end }}

{{- define "oceanbase-cluster.compdef" }}
  {{- if gt (int .Values.obClusters) 1 }}
  {{- printf "%s-repl" (include "oceanbase-release.name" .)}}
  {{- else }}
  {{- include "oceanbase-release.name" . }}
  {{- end }}
{{- end }}


{{- define "oceanbase-cluster.annotations.extra-envs" -}}
 "kubeblocks.io/extra-env": {{ include "oceanbase-cluster.extra-envs" . | nospace  | quote }}
{{- end -}}

{{/*
Define oceanbase cluster annotation pod-ordinal-svc feature gate.
*/}}
{{- define "oceanbase-cluster.featureGate" -}}
kubeblocks.io/enabled-pod-ordinal-svc: {{ include "observers" . | quote}}
{{- end -}}

{{- define "observers" -}}
{{- $observers := list -}}
{{- $nodeCount := .Values.obClusters | int }}
{{- range $idx := until $nodeCount -}}
{{- $observers = print "ob-bundle-" $idx | append $observers -}}
{{- end -}}
{{- join "," $observers -}}
{{- end -}}