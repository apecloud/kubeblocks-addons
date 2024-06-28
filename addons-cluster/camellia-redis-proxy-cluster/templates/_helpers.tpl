{{/*
Define camellia redis proxy componentSpec with ComponentDefinition.
*/}}
{{- define "camellia-redis-proxy-cluster.componentSpec" }}
  componentSpecs:
    - name: proxy
      componentDef: camellia-redis-proxy
      {{- include "kblib.componentMonitor" . | indent 6 }}
      {{- include "camellia-redis-proxy.replicaCount" . | indent 6 }}
      serviceAccountName: {{ include "kblib.serviceAccountName" . }}
      {{- include "kblib.componentResources" . | indent 6 }}
      {{- include "kblib.componentStorages" . | indent 6 }}
      {{- include "kblib.componentServices" . | indent 6 }}
{{- end }}

{{/*
Define replica count.
*/}}
{{- define "camellia-redis-proxy.replicaCount" }}
replicas: {{ .Values.replicas | default 2 }}
{{- end }}
