{{- define "syncer.policyRules" -}}
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
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
- apiGroups:
  - "apps.kubeblocks.io"
  resources:
  - clusters
  verbs:
  - get
  - list
{{- end -}}