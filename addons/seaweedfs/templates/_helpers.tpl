{{- define "seaweedfs.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: seaweedfs
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "seaweedfs.annotations" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{ include "kblib.helm.resourcePolicy" . }}
{{- end -}}

{{- define "seaweedfs.cmpdName" -}}
{{ printf "seaweedfs-%s-%s" .component .root.Chart.Version }}
{{- end -}}

{{- define "seaweedfs.image" -}}
{{ printf "%s/%s:%s" .Values.image.registry .Values.image.repository .Values.image.tag }}
{{- end -}}

{{- define "seaweedfs.scriptsName" -}}
{{ printf "seaweedfs-scripts-%s" .Chart.Version }}
{{- end -}}

{{- define "seaweedfs.filerConfigName" -}}
{{ printf "seaweedfs-filer-config-%s" .Chart.Version }}
{{- end -}}

{{- define "seaweedfs.scripts" -}}
scripts:
  - name: scripts
    template: {{ include "seaweedfs.scriptsName" . }}
    namespace: {{ .Release.Namespace }}
    volumeName: scripts
    defaultMode: 0555
{{- end -}}

{{- define "seaweedfs.identityVars" -}}
- name: SEAWEEDFS_POD_FQDNS
  valueFrom:
    componentVarRef:
      optional: false
      podFQDNs: Required
{{- end -}}

{{- define "seaweedfs.masterVars" -}}
- name: SEAWEEDFS_MASTER_FQDNS
  valueFrom:
    componentVarRef:
      compDef: ^seaweedfs-master-
      optional: false
      podFQDNs: Required
{{- end -}}

{{- define "seaweedfs.podSecurityContext" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  fsGroupChangePolicy: OnRootMismatch
{{- end -}}
