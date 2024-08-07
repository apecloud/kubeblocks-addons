{{/*
Define cluster definition name, if resourceNamePrefix is specified, use it as clusterDefName
*/}}
{{- define "rabbitmq.clusterDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
rabbitmq
{{- else -}}
{{- .Values.resourceNamePrefix -}}
{{- end -}}
{{- end -}}

{{/*
Define component definition name
*/}}
{{- define "rabbitmq.componentDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
rabbitmq
{{- else -}}
{{- .Values.resourceNamePrefix -}}
{{- end -}}
{{- end -}}

{{/*
Define config constriant name
*/}}
{{- define "rabbitmq.configConstraintName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
rabbitmq-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-constraints
{{- end -}}
{{- end -}}

{{- define "rabbitmq.configTplName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
rabbitmq-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-template
{{- end -}}
{{- end -}}

{{- define "rabbitmq.cmScriptsName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
rabbitmq-scripts
{{- else -}}
{{- .Values.resourceNamePrefix -}}-scripts
{{- end -}}
{{- end -}}
