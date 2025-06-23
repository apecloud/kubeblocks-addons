{{/*
Define cluster definition name, if resourceNamePrefix is specified, use it as clusterDefName
*/}}
{{- define "rocketmq.clusterDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
rocketmq
{{- else -}}
{{- .Values.resourceNamePrefix -}}
{{- end -}}
{{- end -}}

{{/*
Define rocketmq component definition name prefix
*/}}
{{- define "rocketmq.cmpdNamePrefix" -}}
{{- default "rocketmq" .Values.resourceNamePrefix -}}-
{{- end -}}

{{/*
Define rocketmq component definition name
*/}}
{{- define "rocketmq.cmpdName" -}}
{{ include "rocketmq.cmpdNamePrefix" . }}{{ .Chart.Version }}
{{- end -}}

{{/*
Define rocketmq pcr definition name
*/}}
{{- define "rocketmq.pcrName" -}}
{{ include "rocketmq.cmpdNamePrefix" . }}pcr
{{- end -}}

{{/*
Define rocketmq pcr definition name
*/}}
{{- define "rocketmq.paramsDefName" -}}
{{ include "rocketmq.cmpdNamePrefix" . }}pd
{{- end -}}

{{/*
Define config constriant name
*/}}
{{- define "rocketmq.configConstraintName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
rocketmq-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-constraints
{{- end -}}
{{- end -}}

{{- define "rocketmq.configTplName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
rocketmq-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-template
{{- end -}}
{{- end -}}

{{- define "rocketmq.cmScriptsName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
rocketmq-scripts
{{- else -}}
{{- .Values.resourceNamePrefix -}}-scripts
{{- end -}}
{{- end -}}
