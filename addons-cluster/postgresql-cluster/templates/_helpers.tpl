{{/*
Define replica count.
standalone mode: 1
replication mode: 2
*/}}
{{- define "postgresql-cluster.replicaCount" }}
{{- if eq .Values.mode "standalone" }}
replicas: 1
{{- else if eq .Values.mode "replication" }}
replicas: {{ max .Values.replicas 2 }}
{{- end }}
{{- end }}

{{/*
Define postgresql ComponentSpec with ComponentDefinition.
*/}}
{{- define "postgresql-cluster.componentSpec" }}
  clusterDefinitionRef: postgresql
  topology: {{ .Values.mode }}
  componentSpecs:
    - name: postgresql
      {{- include "postgresql-cluster.replicaCount" . | indent 6 }}
      enabledLogs:
        - running
      serviceAccountName: {{ include "kblib.serviceAccountName" . }}
      {{- include "kblib.componentMonitor" . | indent 6 }}
      {{- include "kblib.componentResources" . | indent 6 }}
      {{- include "kblib.componentStorages" . | indent 6 }}
      {{- include "kblib.componentServices" . | indent 6 }}
{{- end }}