{{/*
Define neon-compute component definition name
*/}}
{{- define "neon-compute.componentDefName" -}}
neon-compute-{{ .Chart.Version }}
{{- end -}}

{{/*
Define neon-compute component definition regex pattern
*/}}
{{- define "neon-compute.cmpdRegexpPattern" -}}
^neon-compute-
{{- end -}}

{{/*
Define neon-pageserver component definition name
*/}}
{{- define "neon-pageserver.componentDefName" -}}
neon-pageserver-{{ .Chart.Version }}
{{- end -}}

{{/*
Define neon-pageserver component definition regex pattern
*/}}
{{- define "neon-pageserver.cmpdRegexpPattern" -}}
^neon-pageserver-
{{- end -}}

{{/*
Define neon-safekeeper component definition name
*/}}
{{- define "neon-safekeeper.componentDefName" -}}
neon-safekeeper-{{ .Chart.Version }}
{{- end -}}

{{/*
Define neon-safekeeper component definition regex pattern
*/}}
{{- define "neon-safekeeper.cmpdRegexpPattern" -}}
^neon-safekeeper-
{{- end -}}

{{/*
Define neon-storagebroker component definition name
*/}}
{{- define "neon-storagebroker.componentDefName" -}}
neon-broker-{{ .Chart.Version }}
{{- end -}}

{{/*
Define neon-storagebroker component definition regex pattern
*/}}
{{- define "neon-storagebroker.cmpdRegexpPattern" -}}
^neon-broker-
{{- end -}}

{{/*
Define neon configuration template name
*/}}
{{- define "neon.configTemplateName" -}}
neon-config-template
{{- end -}}


{{/*
Define neon scripts template name
*/}}
{{- define "neon.scriptsTemplateName" -}}
neon-scripts-template
{{- end -}}

{{/*
Define image
*/}}
{{- define "neon-compute.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{- define "neon-pageserver.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{- define "neon-safekeeper.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{- define "neon-storagebroker.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end }}