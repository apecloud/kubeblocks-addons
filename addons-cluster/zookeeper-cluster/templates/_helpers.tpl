{{/*
Create extra envs annotations
*/}}
{{- define "zookeeper-cluster.annotations.extra-envs" -}}
"kubeblocks.io/extra-env": {{ include "zookeeper-cluster.extra-envs" . | nospace  | quote }}
{{- end -}}

{{/*
Create extra env
*/}}
{{- define "zookeeper-cluster.extra-envs" -}}
{
"ZOOKEEPER_DYNAMIC_CONFIG_FILE": "{{ .Values.standaloneEnabled }}",
}
{{- end -}}