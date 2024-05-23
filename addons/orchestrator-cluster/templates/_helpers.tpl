{{/*
Create extra env
*/}}
# TOPOLOGY and META user name are fixed to orchestrator
# "ORC_TOPOLOGY_USER": "{{ .Values.secret.TOPOLOGY_USER | default "orchestrator" }}",
# "ORC_META_USER": "{{ .Values.secret.META_USER | default "orchestrator" }}",
{{- define "orchestrator-cluster.extra-envs" }}
{
"ORC_TOPOLOGY_PASSWORD": "{{ .Values.secret.TOPOLOGY_PASSWORD | default "orchestrator" }}",
"ORC_META_PASSWORD": "{{ .Values.secret.META_PASSWORD | default "orchestrator" }}",
"ORC_META_DATABASE": "{{ .Values.secret.META_DATABASE | default "orchestrator" }}"
}
{{- end }}

{{/*
Create the hummock option
*/}}
{{- define "orchestrator-cluster.annotations.extra-envs" -}}
"kubeblocks.io/extra-env": {{ include "orchestrator-cluster.extra-envs" . | nospace  | quote }}
{{- end -}}