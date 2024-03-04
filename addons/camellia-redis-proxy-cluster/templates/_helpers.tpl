{{/*
Define common fileds of cluster object
*/}}
{{- define "camellia-redis-proxy.clusterCommon" }}
apiVersion: apps.kubeblocks.io/v1alpha1
kind: Cluster
metadata:
  name: {{ include "kblib.clusterName" . }}
  namespace: {{ .Release.Namespace }}
  labels: {{ include "kblib.clusterLabels" . | nindent 4 }}
spec:
  terminationPolicy: {{ .Values.extra.terminationPolicy }}
  {{- include "kblib.affinity" . | indent 2 }}
{{- end }}

{{/*
Define replica count.
*/}}
{{- define "camellia-redis-proxy.replicaCount" }}
replicas: {{ .Values.replicas | default 2 }}
{{- end }}
