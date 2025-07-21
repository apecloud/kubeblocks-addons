{{/*
Data volume claim
*/}}
{{- define "milvus.vct.data" }}
- name: data
  spec:
    storageClassName: {{ .Values.persistence.data.storageClassName }}
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: {{ .Values.persistence.data.size }}
{{- end }}

{{/*
External meta storage service reference
*/}}
{{- define "milvus.serviceRef.meta" }}
{{- if eq .Values.storage.meta.mode "serviceref" }}
- name: milvus-meta-storage
  namespace: {{ .Values.storage.meta.serviceRef.namespace }}
  {{- if not .Values.storage.object.serviceRef.serviceDescriptor }}
  clusterServiceSelector:
    cluster: {{ .Values.storage.meta.serviceRef.cluster.name }}
    service:
      component: {{ .Values.storage.meta.serviceRef.cluster.component }}
      service: {{ .Values.storage.meta.serviceRef.cluster.service }}
      port: {{ .Values.storage.meta.serviceRef.cluster.port }}
    # credential:
    #   component: {{ .Values.storage.meta.serviceRef.cluster.component }}
    #   name: {{ .Values.storage.meta.serviceRef.cluster.credential }}
  {{- else }}
  serviceDescriptor: {{ .Values.storage.meta.serviceRef.serviceDescriptor }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
External log storage service reference
*/}}
{{- define "milvus.serviceRef.log" }}
{{- if eq .Values.storage.log.mode "serviceref" }}
- name: milvus-log-storage-kafka
  namespace: {{ .Values.storage.log.serviceRef.namespace }}
  {{- if not .Values.storage.object.serviceRef.serviceDescriptor }}
  clusterServiceSelector:
    cluster: {{ .Values.storage.log.serviceRef.cluster.name }}
    service:
      component: {{ .Values.storage.log.serviceRef.cluster.component }}
      service: {{ .Values.storage.log.serviceRef.cluster.service }}
      port: {{ .Values.storage.log.serviceRef.cluster.port }}
    # credential:
    #   component: {{ .Values.storage.log.serviceRef.cluster.component }}
    #   name: {{ .Values.storage.log.serviceRef.cluster.credential }}
  {{- else }}
  serviceDescriptor: {{ .Values.storage.log.serviceRef.serviceDescriptor }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
External object storage service reference
*/}}
{{- define "milvus.serviceRef.object" }}
{{- if eq .Values.storage.object.mode "serviceref" }}
- name: milvus-object-storage
  namespace: {{ .Release.Namespace }}
  {{- if not .Values.storage.object.serviceRef.serviceDescriptor }}
  clusterServiceSelector:
    cluster: {{ .Values.storage.log.serviceRef.cluster.name }}
    service:
      component: {{ .Values.storage.log.serviceRef.cluster.component }}
      service: {{ .Values.storage.log.serviceRef.cluster.service }}
      port: {{ .Values.storage.log.serviceRef.cluster.port }}
    # credential:
    #   component: {{ .Values.storage.log.serviceRef.cluster.component }}
    #   name: {{ .Values.storage.log.serviceRef.cluster.credential }}
  {{- else }}
  serviceDescriptor: {{ .Values.storage.log.serviceRef.serviceDescriptor }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "milvus.objectstorage.env" }}
- name: MINIO_BUCKET
  value: {{ .Values.storage.object.bucket }}
- name: MINIO_ROOT_PATH
  value: {{ .Values.storage.object.path }}
- name: MINIO_USE_PATH_STYLE
  value: {{ .Values.storage.object.usePathStyle }}
{{- end -}}
