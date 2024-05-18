
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
Define neon-storbroker component defintion name
*/}}
{{- define "neon-storagebroker.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
neon-storbroker
{{- else -}}
{{- printf "neon-storbroker-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define neon-compute component defintion name prefix
*/}}
{{- define "neon-compute.componentDefNamePrefix" -}}
{{- printf "neon-compute-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}

{{/*
Define neon-pageserver component defintion name prefix
*/}}
{{- define "neon-pageserver.componentDefNamePrefix" -}}
{{- printf "neon-pageserver-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}

{{/*
Define neon-safekeeper component defintion name prefix
*/}}
{{- define "neon-safekeeper.componentDefNamePrefix" -}}
{{- printf "neon-safekeeper-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}

{{/*
Define neon-storbroker component defintion name prefix
*/}}
{{- define "neon-storbroker.componentDefNamePrefix" -}}
{{- printf "neon-storbroker-%s" .Values.compDefinitionVersionSuffix -}}
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