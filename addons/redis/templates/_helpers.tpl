{{/*
Expand the name of the chart.
*/}}
{{- define "redis.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

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
Common annotations
*/}}
{{- define "redis.annotations" -}}
helm.sh/resource-policy: keep
{{- end }}

{{/*
Selector labels
*/}}
{{- define "redis.selectorLabels" -}}
app.kubernetes.io/name: {{ include "redis.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Define redis component definition regular expression name prefix
*/}}
{{- define "redis.cmpdRegexpPattern" -}}
^redis-\d+
{{- end -}}

{{/*
Define redis 7.X component definition regular expression name prefix
*/}}
{{- define "redis7.cmpdRegexpPattern" -}}
^redis-7.*
{{- end -}}

{{/*
Define redis sentienl component definition regular expression name prefix
*/}}
{{- define "redisSentinel.cmpdRegexpPattern" -}}
^redis-sentinel-\d+
{{- end -}}

{{/*
Define redis sentienl 7.X component definition regular expression name prefix
*/}}
{{- define "redisSentinel7.cmpdRegexpPattern" -}}
^redis-sentinel-7.*
{{- end -}}

{{/*
Define redis cluster component definition regular expression name prefix
*/}}
{{- define "redisCluster.cmpdRegexpPattern" -}}
^redis-cluster-\d+
{{- end -}}

{{/*
Define redis cluster 7.X component definition regular expression name prefix
*/}}
{{- define "redisCluster7.cmpdRegexpPattern" -}}
^redis-cluster-7.*
{{- end -}}

{{/*
Define redis twemproxy component definition regular expression name prefix
*/}}
{{- define "redisTwemproxy.cmpdRegexpPattern" -}}
^redis-twemproxy-\d+
{{- end -}}

{{/*
Define redis twemproxy 0.5.X component definition regular expression name prefix
*/}}
{{- define "redisTwemproxy05.cmpdRegexpPattern" -}}
^redis-twemproxy-0\.5.*
{{- end -}}

{{/*
Define redis 7.X component definition name
*/}}
{{- define "redis7.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.redis.major7.minorAll ) 0 -}}
redis-7-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.redis.major7.minorAll -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define redis sentinel 7.X component definition name
*/}}
{{- define "redisSentinel7.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.redisSentinel.major7.minorAll ) 0 -}}
redis-sentinel-7-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.redisSentinel.major7.minorAll -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define redis-cluster 7.X component definition name
*/}}
{{- define "redisCluster7.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.redisCluster.major7.minorAll ) 0 -}}
redis-cluster-7-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.redisCluster.major7.minorAll -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define redis-twemproxy 0.5.X component definition name
*/}}
{{- define "redisTwemproxy05.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.redisTwemproxy.major05.minorAll ) 0 -}}
redis-twemproxy-0.5-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.redisTwemproxy.major05.minorAll -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define redis 7.X component configuration template name
*/}}
{{- define "redis7.configurationTemplate" -}}
redis7-config-template-{{ .Chart.Version }}
{{- end -}}

{{/*
Define redis cluster component 7.X configuration template name
*/}}
{{- define "redisCluster7.configurationTemplate" -}}
redis-cluster7-config-template-{{ .Chart.Version }}
{{- end -}}

{{/*
Define redis 7.X component script template name
*/}}
{{- define "redis7.scriptsTemplate" -}}
redis7-scripts-template-{{ .Chart.Version }}
{{- end -}}

{{/*
Define redis cluster 7.X component script template name
*/}}
{{- define "redisCluster7.scriptsTemplate" -}}
redis-cluster7-scripts-template-{{ .Chart.Version }}
{{- end -}}

{{/*
Define redis 7.X component config constraint name
*/}}
{{- define "redis7.configConstraint" -}}
redis7-config-cc
{{- end -}}

{{/*
Define redis cluster 7.X component config constraint name
*/}}
{{- define "redisCluster7.configConstraint" -}}
redis-cluster7-cc
{{- end -}}

{{/*
Define redis metrics config name
*/}}
{{- define "redis.metricsConfiguration" -}}
redis-metrics-config
{{- end -}}

{{/*
Define image
*/}}
{{- define "redis.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "redis7.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag.major7.minor72 }}
{{- end }}

{{- define "redisSentinel.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "redisSentinel7.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag.major7.minor72 }}
{{- end }}

{{- define "redisTwemproxy.repository" -}}
{{ .Values.redisTwemproxyImage.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.redisTwemproxyImage.repository }}
{{- end }}

{{- define "redisTwemproxy05.image" -}}
{{ .Values.redisTwemproxyImage.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.redisTwemproxyImage.repository }}:{{ .Values.redisTwemproxyImage.tag }}
{{- end }}

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
{{ .Values.apeDtsImage.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.apeDtsImage.repository}}:{{ .Values.apeDtsImage.tag }}
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