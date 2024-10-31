{{/*
Define common fileds of cluster object
*/}}
{{- define "kblib.clusterCommon" }}
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: {{ include "kblib.clusterName" . }}
  namespace: {{ .Release.Namespace }}
  labels: {{ include "kblib.clusterLabels" . | nindent 4 }}
spec:
  terminationPolicy: {{ .Values.extra.terminationPolicy }}
{{- end }}
