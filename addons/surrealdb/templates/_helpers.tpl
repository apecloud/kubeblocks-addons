{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tidb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tidb.labels" -}}
helm.sh/chart: {{ include "tidb.chart" . }}
{{ include "tidb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tidb.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "tidb.cmScriptsName" -}}
tidb-scripts
{{- end -}}

{{- define "tidb.tikv.configTplName" -}}
tikv-config-template
{{- end -}}

{{- define "tidb.pd.configTplName" -}}
tidb-pd-config-template
{{- end -}}

{{- define "tidb.tikv.configConstraintName" -}}
tikv-config-constraints
{{- end -}}

{{- define "tidb.pd.configConstraintName" -}}
tidb-pd-config-constraints
{{- end -}}
