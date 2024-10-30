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
  clusterDef: postgresql
  topology: {{ .Values.mode }}
  componentSpecs:
    - name: {{ include "postgresql-cluster.component-name" . }}
      labels:
        {{- include "postgresql-cluster.patroni-scope-label" . | indent 8 }}
      {{- include "postgresql-cluster.replicaCount" . | indent 6 }}
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

{{/*
Define postgresql componentName
*/}}
{{- define "postgresql-cluster.component-name" -}}
postgresql
{{- end }}

{{/*
Define patroni scope label which postgresql cluster depends on, the named pattern is `apps.kubeblocks.postgres.patroni/scope: <clusterName>-<componentName>`
*/}}
{{- define "postgresql-cluster.patroni-scope-label" }}
apps.kubeblocks.postgres.patroni/scope: {{ include "kblib.clusterName" . }}-{{ include "postgresql-cluster.component-name" . }}
{{- end -}}
