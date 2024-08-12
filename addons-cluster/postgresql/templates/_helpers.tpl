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
      {{- if .Values.etcd.proxyEnabled }}
      serviceRefs:
      {{ include "postgresql-cluster.serviceRef" . | indent 6 }}
      {{- end }}
{{- end }}

{{- define "postgresql-cluster.serviceRef" }}
- name: etcd
  namespace: {{ .Release.Namespace }}
  {{- if eq .Values.etcd.meta.mode "incluster" }}
  clusterServiceSelector:
    cluster: {{ .Values.etcd.meta.serviceRef.cluster.name }}
    service:
      component: {{ .Values.etcd.meta.serviceRef.cluster.component }}
      service: {{ .Values.etcd.meta.serviceRef.cluster.service }}
      port: {{ .Values.etcd.meta.serviceRef.cluster.port }}
    credential:
      component: {{ .Values.etcd.meta.serviceRef.cluster.component }}
      name: {{ .Values.etcd.meta.serviceRef.cluster.credential }}
  {{- else }}
  serviceDescriptor: {{ .Values.etcd.meta.serviceRef.serviceDescriptor }}
  {{- end }}
{{- end -}}

