{{/*
Define fields of ComponentDefinition kb version annotation
*/}}
{{- define "kblib.cmpdkbversion" -}}
addon.kubeblocks.io/kubeblocks-version: "{{ .Values.cmpdKBVersion }}"
{{- end }}

{{/*
Define fields of ClusterDefinition kb version annotation
*/}}
{{- define "kblib.cdkbversion" -}}
addon.kubeblocks.io/kubeblocks-version: "{{ .Values.cdKBVersion }}"
{{- end }}

{{/*
Define fields of ComponentVersion kb version annotation
*/}}
{{- define "kblib.cmpvkbversion" -}}
addon.kubeblocks.io/kubeblocks-version: "{{ .Values.cmpvKBVersion }}"
{{- end }}