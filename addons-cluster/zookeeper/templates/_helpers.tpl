{{- define "zookeeper-cluster.extra-envs" }}
{
"ZOOKEEPER_IMAGE_VERSION": "{{ .Values.version }}"
}
{{- end }}

{{/*
Create the hummock option
*/}}
{{- define "zookeeper-cluster.annotations.extra-envs" -}}
"kubeblocks.io/extra-env": {{ include "zookeeper-cluster.extra-envs" . | nospace  | quote }}
{{- end -}}