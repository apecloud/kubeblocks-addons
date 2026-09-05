{{/*
Expand the name of the chart.
*/}}
{{- define "redis.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
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
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "redis.apiVersion" . }}
apps.kubeblocks.io/skip-immutable-check: "true"
{{- end }}

{{/*
API version annotation
*/}}
{{- define "redis.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
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
Define redis component script template name
*/}}
{{- define "redis.scriptsTemplate" -}}
redis-scripts-template-{{ .Chart.Version }}
{{- end -}}

{{/*
Define redis cluster component script template name
*/}}
{{- define "redisCluster.scriptsTemplate" -}}
redis-cluster-scripts-template-{{ .Chart.Version }}
{{- end -}}

{{- define "redis.officialRegistry" -}}
apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com
{{- end }}

{{- define "redis.officialRepository" -}}
{{- $registry := .registry | default "docker.io" -}}
{{- $repository := .repository -}}
{{- if ne $registry (include "redis.officialRegistry" .) -}}
{{- $repository -}}
{{- else if hasPrefix "apecloud/" $repository -}}
{{- $repository -}}
{{- else if eq $repository "redis" -}}
apecloud/redis
{{- else if eq $repository "redis/redis-stack-server" -}}
apecloud/redis-stack-server
{{- else if eq $repository "malexer/twemproxy" -}}
apecloud/twemproxy
{{- else if eq $repository "oliver006/redis_exporter" -}}
apecloud/redis_exporter
{{- else if eq $repository "busybox" -}}
apecloud/busybox
{{- else -}}
{{- $repository -}}
{{- end -}}
{{- end }}

{{- define "redis.qualifiedRepository" -}}
{{- $registry := .registry | default "docker.io" -}}
{{- $repository := include "redis.officialRepository" . | trim -}}
{{- printf "%s/%s" $registry $repository -}}
{{- end }}

{{- define "redis.imagePullPolicy" -}}
{{ default "IfNotPresent" .Values.image.pullPolicy }}
{{- end }}

{{- define "redis.dbctlImagePullPolicy" -}}
{{ default "IfNotPresent" .Values.dbctlImage.pullPolicy }}
{{- end }}

{{- define "redis.metricsImagePullPolicy" -}}
{{ default "IfNotPresent" .Values.metrics.image.pullPolicy }}
{{- end }}

{{- define "redis7.image" -}}
{{- $registry := .Values.image.registry | default "docker.io" -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := .Values.image.tag.major7.minor72 -}}
{{- range .Values.redisVersions -}}
{{- if eq .major "7" -}}
{{- $repository = .repository | default $repository -}}
{{- $tag = .defaultImageTag | default $tag -}}
{{- end -}}
{{- end -}}
{{ include "redis.qualifiedRepository" (dict "registry" $registry "repository" $repository) | trim }}:{{ $tag }}
{{- end }}

{{- define "redisTwemproxy.repository" -}}
{{- $registry := .Values.redisTwemproxyImage.registry | default ( .Values.image.registry | default "docker.io" ) -}}
{{- include "redis.qualifiedRepository" (dict "registry" $registry "repository" .Values.redisTwemproxyImage.repository) | trim -}}
{{- end }}

{{- define "redisTwemproxy05.image" -}}
{{ include "redisTwemproxy.repository" . }}:{{ .Values.redisTwemproxyImage.tag }}
{{- end }}

{{- define "busybox.image" -}}
{{ $registry := .Values.busyboxImage.registry | default ( .Values.image.registry | default "docker.io" )}}
{{- if eq $registry (include "redis.officialRegistry" .) -}}
{{ $registry }}/apecloud/busybox:{{ .Values.busyboxImage.tag }}
{{- else -}}
{{ $registry }}/{{ .Values.busyboxImage.repository | default "busybox" }}:{{ .Values.busyboxImage.tag }}
{{- end -}}
{{- end }}

{{- define "metrics.repository" -}}
{{- $registry := .Values.metrics.image.registry | default ( .Values.image.registry | default "docker.io" ) -}}
{{- include "redis.qualifiedRepository" (dict "registry" $registry "repository" .Values.metrics.image.repository) | trim -}}
{{- end }}

{{- define "metrics.image" -}}
{{ include "metrics.repository" . }}:{{ .Values.metrics.image.tag }}
{{- end }}

{{- define "apeDts.image" -}}
{{ .Values.apeDtsImage.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.apeDtsImage.repository}}:{{ .Values.apeDtsImage.tag }}
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
{{- if $.Files.Get "scripts/redis-account.sh" }}
redis-account.sh: |-
{{- $.Files.Get "scripts/redis-account.sh" | nindent 2 }}
{{- end }}
{{- end }}

{{- define "apeDts.reshard.image" -}}
{{ .Values.image.apeDts.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.image.apeDts.repository}}:{{ .Values.image.apeDts.reshardTag }}
{{- end }}

{{- define "redis.ceRepository" -}}
{{ $registry := .Values.ceImage.registry | default ( .Values.image.registry | default "docker.io" )}}
{{- if eq $registry (include "redis.officialRegistry" .) -}}
apecloud/redis
{{- else -}}
{{- .Values.ceImage.repository -}}
{{- end -}}
{{- end -}}
