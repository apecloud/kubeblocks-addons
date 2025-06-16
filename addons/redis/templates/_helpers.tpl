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

{{/*
Define redis metrics config name
*/}}
{{- define "redis.metricsConfiguration" -}}
redis-metrics-config
{{- end -}}

{{- define "redis7.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag.major7.minor72 }}
{{- end }}

{{- define "redis8.image" -}}
{{ .Values.ceImage.registry | default "docker.io" }}/{{ .Values.ceImage.repository }}:{{ .Values.image.tag.major8.minor80 }}
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
