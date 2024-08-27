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
redis
{{- else -}}
{{- printf "redis-%s" .Values.compDefinitionVersion.redis -}}
{{- end -}}
{{- end -}}

{{/*
Define redis component defintion name prefix
*/}}
{{- define "redis.componentDefNamePrefix" -}}
{{- printf "redis-%s" .Values.compDefinitionVersion.redis -}}
{{- end -}}

{{/*
Define redis-sentinel component defintion name
*/}}
{{- define "redis-sentinel.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersion.sentinel) 0 -}}
redis-sentinel
{{- else -}}
{{- printf "redis-sentinel-%s" .Values.compDefinitionVersion.sentinel -}}
{{- end -}}
{{- end -}}

{{/*
Define redis-sentinel component defintion name prefix
*/}}
{{- define "redis-sentinel.componentDefNamePrefix" -}}
{{- printf "redis-sentinel-%s" .Values.compDefinitionVersion.sentinel -}}
{{- end -}}

{{/*
Define redis-cluster component defintion name
*/}}
{{- define "redis-cluster.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersion.redisCluster) 0 -}}
redis-cluster
{{- else -}}
{{- printf "redis-cluster-%s" .Values.compDefinitionVersion.redisCluster -}}
{{- end -}}
{{- end -}}

{{/*
Define redis-cluster component defintion name prefix
*/}}
{{- define "redis-cluster.componentDefNamePrefix" -}}
{{- printf "redis-cluster-%s" .Values.compDefinitionVersion.redisCluster -}}
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
{{- define "redis.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "redis.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag.major7.minor72 }}
{{- end }}

{{- define "redis-sentinel.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "redis-sentinel.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag.major7.minor72 }}
{{- end }}

{{- define "redis-twemproxy.repository" -}}
{{ .Values.redisTwemproxyImage.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.redisTwemproxyImage.repository }}
{{- end }}

{{- define "redis-twemproxy.image" -}}
{{ .Values.redisTwemproxyImage.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.redisTwemproxyImage.repository }}:{{ .Values.redisTwemproxyImage.tag }}
{{- end }}

{{- define "busybox.repository" -}}
{{ .Values.busyboxImage.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.busyboxImage.repository}}
{{- end }}}

{{- define "busybox.image" -}}
{{ .Values.busyboxImage.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.busyboxImage.repository}}:{{ .Values.busyboxImage.tag }}
{{- end }}}

{{- define "metrics.repository" -}}
{{ .Values.metrics.image.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.metrics.image.repository}}
{{- end }}}

{{- define "metrics.image" -}}
{{ .Values.metrics.image.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.metrics.image.repository}}:{{ .Values.metrics.image.tag }}
{{- end }}}

{{- define "apeDts.image" -}}
{{ .Values.image.apeDts.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.image.apeDts.repository}}:{{ .Values.image.apeDts.tag }}
{{- end }}}


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