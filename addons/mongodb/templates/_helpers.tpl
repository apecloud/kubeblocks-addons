{{/*
Expand the name of the chart.
*/}}
{{- define "mongodb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mongodb-sharding.name" -}}
{{- default "mongodb-sharding" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mongodb.fullname" -}}
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
{{- define "mongodb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mongodb.labels" -}}
helm.sh/chart: {{ include "mongodb.chart" . }}
{{ include "mongodb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Mongodb-sharding Common labels
*/}}
{{- define "mongodb-sharding.labels" -}}
helm.sh/chart: {{ include "mongodb.chart" . }}
{{ include "mongodb-sharding.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Mongodb-sharding Selector labels
*/}}
{{- define "mongodb-sharding.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mongodb-sharding.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mongodb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mongodb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
Return MongoDB service port
*/}}
{{- define "mongodb.service.port" -}}
{{- .Values.primary.service.ports.mongodb -}}
{{- end -}}

{{/*
Return the name for a custom database to create
*/}}
{{- define "mongodb.database" -}}
{{- .Values.auth.database -}}
{{- end -}}

{{/*
Get the password key.
*/}}
{{- define "mongodb.password" -}}
{{- if or (.Release.IsInstall) (not (lookup "apps.kubeblocks.io/v1alpha1" "ClusterDefinition" "" "mongodb")) -}}
{{ .Values.auth.password | default "$(RANDOM_PASSWD)"}}
{{- else -}}
{{ index (lookup "apps.kubeblocks.io/v1alpha1" "ClusterDefinition" "" "mongodb").spec.connectionCredential "password"}}
{{- end }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "mongodb.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "mongodb.apiVersion" . }}
apps.kubeblocks.io/skip-immutable-check: "true"
{{- end }}

{{/*
API version annotation
*/}}
{{- define "mongodb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define mongodb component definition name prefix
*/}}
{{- define "mongodb.componentDefNamePrefix" -}}
{{- printf "mongodb-" -}}
{{- end -}}

{{/*
Define mongodb component definition name
*/}}
{{- define "mongodb.compDefName" -}}
{{- if eq (len .Values.cmpdVersionPrefix) 0 -}}
mongodb-{{ .Chart.Version }}
{{- else -}}
{{ .Values.cmpdVersionPrefix}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}


{{/*
Define mongodb-shard component definition name
*/}}
{{- define "mongodbShard.compDefName" -}}
{{- if eq (len .Values.cmpdVersionPrefix) 0 -}}
mongo-shard-{{ .Chart.Version }}
{{- else -}}
{{- printf "mongo-shard-%s" .Values.cmpdVersionPrefix -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define mongo-shard component definition name prefix
*/}}
{{- define "mongodbShard.componentDefNamePrefix" -}}
{{- printf "mongo-shard-" -}}
{{- end -}}

{{/*
Define mongos component definition name
*/}}
{{- define "mongos.compDefName" -}}
{{- if eq (len .Values.cmpdVersionPrefix) 0 -}}
mongo-mongos-{{ .Chart.Version }}
{{- else -}}
{{- printf "mongo-mongos-%s" .Values.cmpdVersionPrefix -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define mongos component definition name prefix
*/}}
{{- define "mongos.componentDefNamePrefix" -}}
{{- printf "mongo-mongos-" -}}
{{- end -}}

{{/*
Define config server component definition name
*/}}
{{- define "cfgServer.compDefName" -}}
{{- if eq (len .Values.cmpdVersionPrefix) 0 -}}
mongo-config-server-{{ .Chart.Version }}
{{- else -}}
{{- printf "mongo-config-server-%s" .Values.cmpdVersionPrefix -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define config server component definition name prefix
*/}}
{{- define "cfgServer.componentDefNamePrefix" -}}
{{- printf "mongo-config-server-" -}}
{{- end -}}