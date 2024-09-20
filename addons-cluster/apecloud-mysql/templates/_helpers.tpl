{{/*
Define the cluster componnets with proxy.
The proxy cpu cores is 1/6 of the cluster total cpu cores and is multiple of 0.5.
The minimum proxy cpu cores is 0.5 and the maximum cpu cores is 64.
*/}}
{{- define "apecloud-mysql-cluster.proxyComponents" }}
{{- $replicas := (include "apecloud-mysql-cluster.replicas" .) }}
{{- $proxyCPU := divf (mulf $replicas .Values.cpu) 6.0 }}
{{- $proxyCPU = divf $proxyCPU 0.5 | ceil | mulf 0.5 }}
{{- if lt $proxyCPU 0.5 }}
{{- $proxyCPU = 0.5 }}
{{- else if gt $proxyCPU 64.0 }}
{{- $proxyCPU = 64 }}
{{- end }}
- name: wescale-ctrl
  {{- if not .Values.localEtcdEnabled }}
  serviceRefs:
    {{ include "apecloud-mysql-cluster.serviceRef" . | indent 4 }}
  {{- end }}
  volumeClaimTemplates:
    - name: data
      spec:
        storageClassName: {{ .Values.proxy.storageClassName | quote }}
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi
  replicas: 1
  resources:
    limits:
      cpu: 500m
      memory: 128Mi
- name: wescale
  {{- if not .Values.localEtcdEnabled }}
  serviceRefs:
    {{ include "apecloud-mysql-cluster.serviceRef" . | indent 4 }}
  {{- end }}
  replicas: 1
  enabledLogs:
    - error
    - warning
    - info
    - queryLog
  resources:
    requests:
      cpu: {{ $proxyCPU | quote }}
      memory: 500Mi
    limits:
      cpu: {{ $proxyCPU | quote }}
      memory: 500Mi
{{- end }}

{{/*
Define replicas.
standalone topology: 1
raftGroup topology: max(replicas, 3)
*/}}
{{- define "apecloud-mysql-cluster.replicas" }}
{{- if eq .Values.topology "standalone" }}
{{- 1 }}
{{- else if eq .Values.topology "raftGroup" }}
{{- max .Values.replicas 3 }}
{{- end }}
{{- end -}}

{{- define "apecloud-mysql-cluster.topology" }}
{{- if and (eq .Values.topology "raftGroup") .Values.proxyEnabled }}
  {{- if .Values.localEtcdEnabled }}
    {{- "apecloud-mysql-proxy-etcd" }}
  {{- else }}
    {{- "apecloud-mysql-proxy" }}
  {{- end }}
{{- else }}
  {{- "apecloud-mysql" }}
{{- end -}}
{{- end -}}

{{- define "apecloud-mysql-cluster.serviceRef" }}
- name: etcd
  namespace: {{ .Release.Namespace }}
  serviceDescriptor: {{ include "kblib.clusterName" . }}-etcd-descriptor
{{- end -}}

{{- define "apecloud-mysql-cluster.etcdComponents" }}
- name: etcd
  volumeClaimTemplates:
    - name: data
      spec:
        storageClassName: {{ .Values.proxy.storageClassName | quote }}
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: {{ .Values.etcd.resources.storage }}
  replicas: {{ .Values.etcd.replicas }}
  resources:
    requests:
      cpu: 500m
      memory: 500Mi
    limits:
      cpu: 500m
      memory: 500Mi
{{- end -}}