{{- define "kblib.syncer._policyRules" -}}
policyRules:
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - create
  - get
  - list
  - patch
  - update
  - delete
- apiGroups:
  - ""
  resources:
  - pods
  {{- if .readPersistentVolumeClaims }}
  - persistentvolumeclaims
  {{- end }}
  verbs:
  - get
  - list
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - create
- apiGroups:
  - "apps.kubeblocks.io"
  resources:
  - clusters
  verbs:
  - get
  - list
{{- end -}}

{{- define "kblib.syncer.policyRules" -}}
{{- include "kblib.syncer._policyRules" (dict "readPersistentVolumeClaims" false) -}}
{{- end -}}

{{- define "kblib.syncer.policyRulesWithPersistentVolumeClaims" -}}
{{- include "kblib.syncer._policyRules" (dict "readPersistentVolumeClaims" true) -}}
{{- end -}}


{{- define "kblib.helm.resourcePolicy" -}}
{{- if eq .Values.extra.keepResource true }}
helm.sh/resource-policy: keep
{{- end -}}
{{- end -}}
