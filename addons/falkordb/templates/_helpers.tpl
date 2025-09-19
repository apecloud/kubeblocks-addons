{{/*
Expand the name of the chart.
*/}}
{{- define "falkordb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "falkordb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "falkordb.labels" -}}
helm.sh/chart: {{ include "falkordb.chart" . }}
{{ include "falkordb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "falkordb.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "falkordb.apiVersion" . }}
apps.kubeblocks.io/skip-immutable-check: "true"
{{- end }}

{{/*
API version annotation
*/}}
{{- define "falkordb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Selector labels
*/}}
{{- define "falkordb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "falkordb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Define falkordb component definition regular expression name prefix
*/}}
{{- define "falkordb.cmpdRegexpPattern" -}}
^falkordb-\d+
{{- end -}}

{{/*
Define falkordb 7.X component definition regular expression name prefix
*/}}
{{- define "falkordb7.cmpdRegexpPattern" -}}
^falkordb-7.*
{{- end -}}

{{/*
Define falkordb sentienl component definition regular expression name prefix
*/}}
{{- define "falkordbSentinel.cmpdRegexpPattern" -}}
^falkordb-sent-\d+
{{- end -}}

{{/*
Define falkordb sentienl 7.X component definition regular expression name prefix
*/}}
{{- define "falkordbSentinel7.cmpdRegexpPattern" -}}
^falkordb-sent-7.*
{{- end -}}

{{/*
Define falkordb cluster component definition regular expression name prefix
*/}}
{{- define "falkordbCluster.cmpdRegexpPattern" -}}
^falkordb-cluster-\d+
{{- end -}}

{{/*
Define falkordb cluster 7.X component definition regular expression name prefix
*/}}
{{- define "falkordbCluster7.cmpdRegexpPattern" -}}
^falkordb-cluster-7.*
{{- end -}}


{{/*
Define falkordb component script template name
*/}}
{{- define "falkordb.scriptsTemplate" -}}
falkordb-scripts-template-{{ .Chart.Version }}
{{- end -}}

{{/*
Define falkordb cluster component script template name
*/}}
{{- define "falkordbCluster.scriptsTemplate" -}}
falkordb-cluster-scripts-template-{{ .Chart.Version }}
{{- end -}}

{{/*
Define falkordb metrics config name
*/}}
{{- define "falkordb.metricsConfiguration" -}}
falkordb-metrics-config
{{- end -}}

{{- define "falkordb7.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag.major7.minor72 }}
{{- end }}

{{- define "falkordb8.image" -}}
{{ .Values.ceImage.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.ceImage.repository }}:{{ .Values.image.tag.major8.minor80 }}
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
{{- define "falkordb.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate scripts configmap
*/}}
{{- define "falkordb-cluster.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "falkordb-cluster-scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- if $.Files.Get "scripts/falkordb-account.sh" }}
falkordb-account.sh: |-
{{- $.Files.Get "scripts/falkordb-account.sh" | nindent 2 }}
{{- end }}
{{- end }}

{{- define "apeDts.reshard.image" -}}
{{ .Values.image.apeDts.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.image.apeDts.repository}}:{{ .Values.image.apeDts.reshardTag }}
{{- end }}}
