{{/*
Define cluster definition name, if resourceNamePrefix is specified, use it as clusterDefName
*/}}
{{- define "neo4j.clusterDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
neo4j
{{- else -}}
{{- .Values.resourceNamePrefix -}}
{{- end -}}
{{- end -}}

{{/*
Define neo4j component definition name prefix
*/}}
{{- define "neo4j.cmpdNamePrefix" -}}
{{- default "neo4j" .Values.resourceNamePrefix -}}-
{{- end -}}

{{/*
Define neo4j component definition name
*/}}
{{- define "neo4j.cmpdName" -}}
{{ include "neo4j.cmpdNamePrefix" . }}{{ .Chart.Version }}
{{- end -}}

{{/*
Define neo4j pcr definition name
*/}}
{{- define "neo4j.pcrName" -}}
{{ include "neo4j.cmpdNamePrefix" . }}pcr
{{- end -}}

{{/*
Define neo4j pcr definition name
*/}}
{{- define "neo4j.paramsDefName" -}}
{{ include "neo4j.cmpdNamePrefix" . }}pd
{{- end -}}

{{/*
Define config constriant name
*/}}
{{- define "neo4j.configConstraintName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
neo4j-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-constraints
{{- end -}}
{{- end -}}

{{- define "neo4j.configTplName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
neo4j-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-template
{{- end -}}
{{- end -}}

{{- define "neo4j.cmScriptsName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
neo4j-scripts
{{- else -}}
{{- .Values.resourceNamePrefix -}}-scripts
{{- end -}}
{{- end -}}
