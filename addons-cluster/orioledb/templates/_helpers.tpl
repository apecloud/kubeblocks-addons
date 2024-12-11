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
  topology: replication
  componentSpecs:
    - name: {{ include "orioledb-cluster.component-name" . }}
      serviceVersion: {{ .Values.version }}
      labels:
        {{- include "orioledb-cluster.patroni-scope-label" . | indent 8 }}
      {{- include "kblib.componentMonitor" . | indent 6 }}
      {{- include "orioledb-cluster.replicaCount" . | indent 6 }}
      {{- include "kblib.componentResources" . | indent 6 }}
      {{- include "kblib.componentStorages" . | indent 6 }}
      {{- if .Values.etcd.enabled }}
      serviceRefs:
      {{ include "orioledb-cluster.serviceRef" . | indent 6 }}
      {{- end }}
{{- end }}

{{- define "orioledb-cluster.serviceRef" }}
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
Define orioledb componentName
*/}}
{{- define "orioledb-cluster.component-name" -}}
orioledb
{{- end }}

{{/*
Define patroni scope label which postgresql cluster depends on, the named pattern is `apps.kubeblocks.postgres.patroni/scope: <clusterName>-<componentName>`
*/}}
{{- define "orioledb-cluster.patroni-scope-label" }}
apps.kubeblocks.postgres.patroni/scope: {{ include "kblib.clusterName" . }}-{{ include "orioledb-cluster.component-name" . }}
{{- end -}}
