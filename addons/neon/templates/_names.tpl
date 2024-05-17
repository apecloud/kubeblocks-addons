
{{/*
Define neon-compute component defintion name
*/}}
{{- define "neon-compute.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
neon-compute
{{- else -}}
{{- printf "neon-compute-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define neon-pageserver component defintion name
*/}}
{{- define "neon-pageserver.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
neon-pageserver
{{- else -}}
{{- printf "neon-pageserver-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define neon-safekeeper component defintion name
*/}}
{{- define "neon-safekeeper.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
neon-safekeeper
{{- else -}}
{{- printf "neon-safekeeper-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define neon-safekeeper component defintion name
*/}}
{{- define "neon-storagebroker.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
neon-storbroker
{{- else -}}
{{- printf "neon-storbroker-%s" .Values.compDefinitionVersionSuffix -}}
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