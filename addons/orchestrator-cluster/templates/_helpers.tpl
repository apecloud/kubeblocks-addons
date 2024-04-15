{{/*
Create extra env
*/}}
{{- define "orchestrator-cluster.extra-envs" }}
{
"ORC_TOPOLOGY_USER": "{{ .Values.secret.TOPOLOGY_USER | default "orchestrator" }}",
"ORC_TOPOLOGY_PASSWORD": "{{ .Values.secret.TOPOLOGY_USER | default "orchestrator" }}",
"ORC_META_USER": "{{ .Values.secret.META_USER | default "orchestrator" }}",
"ORC_META_PASSWORD": "{{ .Values.secret.META_PASSWORD | default "orchestrator" }}"
}
{{- end }}

{{/*
Create the hummock option
*/}}
{{- define "orchestrator-cluster.annotations.extra-envs" }}
"kubeblocks.io/extra-env": {{ include "orchestrator-cluster.extra-envs" . | nospace  | quote }}
{{- end }}