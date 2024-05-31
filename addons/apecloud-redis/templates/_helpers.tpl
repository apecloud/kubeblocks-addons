{{/*
Expand the name of the chart.
*/}}
{{- define "redis.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Define redis component defintion name
*/}}
{{- define "redis.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersion.redis) 0 -}}
apecloud-redis
{{- else -}}
{{- printf "apecloud-redis-%s" .Values.compDefinitionVersion.redis -}}
{{- end -}}
{{- end -}}

{{/*
Define redis component defintion name prefix
*/}}
{{- define "redis.componentDefNamePrefix" -}}
{{- printf "apecloud-redis-%s" .Values.compDefinitionVersion.redis -}}
{{- end -}}

{{/*
Define redis-sentinel component defintion name
*/}}
{{- define "redis-sentinel.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersion.sentinel) 0 -}}
apecloud-redis-sentinel
{{- else -}}
{{- printf "apecloud-redis-sentinel-%s" .Values.compDefinitionVersion.sentinel -}}
{{- end -}}
{{- end -}}

{{/*
Define redis-sentinel component defintion name prefix
*/}}
{{- define "redis-sentinel.componentDefNamePrefix" -}}
{{- printf "apecloud-redis-sentinel-%s" .Values.compDefinitionVersion.sentinel -}}
{{- end -}}

{{/*
Define redis-cluster component defintion name
*/}}
{{- define "redis-cluster.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersion.redisCluster) 0 -}}
apecloud-redis-cluster
{{- else -}}
{{- printf "apecloud-redis-cluster-%s" .Values.compDefinitionVersion.redisCluster -}}
{{- end -}}
{{- end -}}

{{/*
Define redis-cluster component defintion name prefix
*/}}
{{- define "redis-cluster.componentDefNamePrefix" -}}
{{- printf "apecloud-redis-cluster-%s" .Values.compDefinitionVersion.redisCluster -}}
{{- end -}}

{{/*
Define redis-twemproxy component defintion name
*/}}
{{- define "redis-twemproxy.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersion.twemproxy) 0 -}}
redis-twemproxy
{{- else -}}
{{- printf "redis-twemproxy-%s" .Values.compDefinitionVersion.twemproxy -}}
{{- end -}}
{{- end -}}

{{/*
Define redis-twemproxy component defintion name prefix
*/}}
{{- define "redis-twemproxy.componentDefNamePrefix" -}}
{{- printf "redis-twemproxy-%s" .Values.compDefinitionVersion.twemproxy -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "redis.fullname" -}}
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
{{- define "redis.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "redis.labels" -}}
helm.sh/chart: {{ include "redis.chart" . }}
{{ include "redis.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "redis.selectorLabels" -}}
app.kubernetes.io/name: {{ include "redis.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Define image
*/}}
{{- define "apecloud-redis.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag.major7.minor70 }}
{{- end }}

{{- define "apecloud-redis-sentinel.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag.major7.minor70 }}
{{- end }}

{{/*
Generate scripts configmap
*/}}
{{- define "redis.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate scripts configmap
*/}}
{{- define "redis-cluster.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "redis-cluster-scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}