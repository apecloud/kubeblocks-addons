{{/*
Define class name
*/}}
{{- define "gbase.className" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
kb.classes.default.gbase
{{- else -}}
{{- .Values.resourceNamePrefix -}}-class
{{- end -}}
{{- end -}}

{{/*
Define cluster definition name, if resourceNamePrefix is specified, use it as clusterDefName
*/}}
{{- define "gbase.clusterDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
gbase
{{- else -}}
{{- .Values.resourceNamePrefix -}}
{{- end -}}
{{- end -}}

{{/*
Define cluster version
*/}}
{{- define "gbase.clusterVersion" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
gbase8c-{{ default .Chart.AppVersion .Values.clusterVersionOverride }}
{{- else -}}
{{- .Values.resourceNamePrefix -}}-{{ default .Chart.AppVersion .Values.clusterVersionOverride }}
{{- end -}}
{{- end -}}

{{/*
Define cluster version with auditlog
*/}}
{{- define "gbase.clusterVersionAuditLog" -}}
{{- include "gbase.clusterVersion" . }}-{{ default "1" .Values.auditlogSubVersion }}
{{- end -}}

{{/*
Define component defintion name
*/}}
{{- define "gbase.componentDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
gbase
{{- else -}}
{{- .Values.resourceNamePrefix -}}
{{- end -}}
{{- end -}}

{{- define "gbase.cmScriptsName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
gbase-scripts
{{- else -}}
{{- .Values.resourceNamePrefix -}}-scripts
{{- end -}}
{{- end -}}

{{- define "gbase.cmConfigName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
gbase-config
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config
{{- end -}}
{{- end -}}