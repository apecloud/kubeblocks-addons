
{{/*
Define neon-compute component defintion name
*/}}
{{- define "neon-compute.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
compute
{{- else -}}
{{- printf "compute-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define neon-pageserver component defintion name
*/}}
{{- define "neon-pageserver.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
pageserver
{{- else -}}
{{- printf "pageserver-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define neon-safekeeper component defintion name
*/}}
{{- define "neon-safekeeper.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
safekeeper
{{- else -}}
{{- printf "safekeeper-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define neon-safekeeper component defintion name
*/}}
{{- define "neon-storagebroker.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
storagebroker
{{- else -}}
{{- printf "storagebroker-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define image
*/}}
{{- define "neon-compute.image" -}}
{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{- define "neon-pageserver.image" -}}
{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{- define "neon-safekeeper.image" -}}
{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{- define "neon-storagebroker.image" -}}
{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end }}