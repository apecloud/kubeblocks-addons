{{/*
Define replica count.
standalone mode: 1
replication mode: 2
*/}}
{{- define "orioledb-cluster.replicaCount" }}
{{- if eq .Values.mode "standalone" }}
replicas: 1
{{- else if eq .Values.mode "replication" }}
replicas: {{ max .Values.replicas 2 }}
{{- end }}
{{- end }}

{{/*
Define orioledb ComponentSpec with ComponentDefinition.
*/}}
{{- define "orioledb-cluster.componentSpec" }}
  clusterDef: orioledb
  topology: orioledb
  componentSpecs:
    - name: {{ include "orioledb-cluster.component-name" . }}
      serviceVersion: {{ .Values.version }}
      {{- include "kblib.componentMonitor" . | indent 6 }}
      {{- include "orioledb-cluster.replicaCount" . | indent 6 }}
      {{- include "kblib.componentResources" . | indent 6 }}
      {{- include "kblib.componentStorages" . | indent 6 }}
{{- end }}


{{/*
Define orioledb componentName
*/}}
{{- define "orioledb-cluster.component-name" -}}
orioledb
{{- end }}
