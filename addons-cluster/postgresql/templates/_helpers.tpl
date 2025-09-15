{{/*
Define replica count.
standalone or standby mode: 1
replication mode: 2
*/}}
{{- define "postgresql-cluster.replicaCount" }}
{{- if or (eq .Values.mode "standalone") .Values.remoteSetting.isStandby }}
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
  topology: replication
  componentSpecs:
    - name: {{ include "postgresql-cluster.component-name" . }}
      serviceVersion: {{ .Values.version }}
      {{- include "kblib.componentMonitor" . | indent 6 }}
      {{- include "postgresql-cluster.replicaCount" . | indent 6 }}
      {{- include "kblib.componentResources" . | indent 6 }}
      {{- include "kblib.componentStorages" . | indent 6 }}
      {{- include "postgresql-cluster.serviceRef" . | indent 6 }}
{{- end }}

{{- define "postgresql-cluster.serviceRef" }}
{{- if or .Values.etcd.enabled (and .Values.remoteSetting.isStandby .Values.remoteSetting.primaryHost .Values.remoteSetting.primaryPort) }}
serviceRefs:
{{- include "postgresql-cluster.etcdServiceRef" . | indent 2 }}
{{- include "postgresql-cluster.remoteServiceRef" . | indent 2 }}
{{- end }}
{{- end -}}

{{- define "postgresql-cluster.etcdServiceRef" }}
{{- if .Values.etcd.enabled }}
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
  {{- end }}
{{- end -}}

{{- define "postgresql-cluster.remoteServiceRef" }}
{{- if and .Values.remoteSetting.isStandby .Values.remoteSetting.primaryHost .Values.remoteSetting.primaryPort }}
- name: remote-instances
  {{- if .Values.remoteSetting.serviceDescriptorNamespace }}
  namespace: {{ .Values.remoteSetting.serviceDescriptorNamespace }}
  {{- end }}
  serviceDescriptor: {{ include "kblib.clusterName" . }}-remote-desc
{{- end }}
{{- end -}}

{{/*
Define postgresql componentName
*/}}
{{- define "postgresql-cluster.component-name" -}}
postgresql
{{- end }}
