{{/*
Expand the name of the chart.
*/}}
{{- define "greptimedb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "greptimedb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "greptimedb.labels" -}}
helm.sh/chart: {{ include "greptimedb.chart" . }}
{{ include "greptimedb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "greptimedb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "greptimedb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "greptimedb.annotations" -}}
helm.sh/resource-policy: keep
{{ include "greptimedb.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "greptimedb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define greptimedb datanode component definition name
*/}}
{{- define "greptimedb-datanode.cmpdName" -}}
greptimedb-datanode-{{ .Chart.Version }}
{{- end -}}

{{/*
Define greptimedb datanode component definition regex pattern
*/}}
{{- define "greptimedb-datanode.cmpdRegexpPattern" -}}
^greptimedb-datanode-
{{- end -}}

{{/*
Define greptimedb frontend component definition name
*/}}
{{- define "greptimedb-frontend.cmpdName" -}}
greptimedb-frontend-{{ .Chart.Version }}
{{- end -}}

{{/*
Define greptimedb frontend component definition regex pattern
*/}}
{{- define "greptimedb-frontend.cmpdRegexpPattern" -}}
^greptimedb-frontend-
{{- end -}}

{{/*
Define greptimedb meta component definition name
*/}}
{{- define "greptimedb-meta.cmpdName" -}}
greptimedb-meta-{{ .Chart.Version }}
{{- end -}}

{{/*
Define greptimedb meta component definition regex pattern
*/}}
{{- define "greptimedb-meta.cmpdRegexpPattern" -}}
^greptimedb-meta-
{{- end -}}

{{/*
Define greptimedb etcd component definition regex pattern
*/}}
{{- define "greptimedb-etcd.cmpdRegexpPattern" -}}
^etcd-
{{- end -}}

{{/*
Define greptimedb datanode configuration template name
*/}}
{{- define "greptimedb-datanode.configTemplateName" -}}
greptimedb-datanode-tpl
{{- end -}}

{{/*
Define greptimedb frontend configuration template name
*/}}
{{- define "greptimedb-frontend.configTemplateName" -}}
greptimedb-frontend-tpl
{{- end -}}

{{/*
Define greptimedb meta configuration template name
*/}}
{{- define "greptimedb-meta.configTemplateName" -}}
greptimedb-meta-tpl
{{- end -}}
