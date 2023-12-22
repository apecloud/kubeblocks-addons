{{/*
Define redis cluster sentinel component.
*/}}
{{- define "redis-cluster.sentinel" }}
- componentDef: redis-sentinel
  name: redis-sentinel
  replicas: {{ .Values.sentinel.replicas }}
  resources:
    limits:
      cpu: {{ .Values.sentinel.cpu | quote }}
      memory:  {{ print .Values.sentinel.memory "Gi" | quote }}
    requests:
      cpu: {{ .Values.sentinel.cpu | quote }}
      memory:  {{ print .Values.sentinel.memory "Gi" | quote }}
  volumeClaimTemplates:
    - name: data
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: {{ print .Values.sentinel.storage "Gi" }}
{{- end }}


{{/*
Define redis cluster sentinel nodeport service.
*/}}
{{- define "redis-cluster.sentinel-nodeport" }}
- name: redis-sentinel-nodeport
  serviceName: redis-sentinel-nodeport
  generatePodOrdinalService: true
  componentSelector: redis-sentinel
  spec:
    type: NodePort
    ports:
    - name: redis-sentinel-nodeport
      port: 26379
      targetPort: 26379
{{- end }}

{{/*
Define replica count.
standalone mode: 1
replication mode: 2
*/}}
{{- define "redis-cluster.replicaCount" }}
{{- if eq .Values.mode "standalone" }}
replicas: 1
{{- else if eq .Values.mode "replication" }}
replicas: {{ max .Values.replicas 2 }}
{{- end }}
{{- end }}