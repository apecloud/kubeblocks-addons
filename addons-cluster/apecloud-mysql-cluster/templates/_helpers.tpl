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
- name: wescale-vtctld
  serviceRefs:
    {{ include "apecloud-mysql-cluster.serviceRef" . | indent 4 }}
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
- name: wescale-vtgate
  serviceRefs:
    {{ include "apecloud-mysql-cluster.serviceRef" . | indent 4 }}
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
- name: wescale-vttablet
  serviceRefs:
    {{ include "apecloud-mysql-cluster.serviceRef" . | indent 4 }}
  replicas: {{ include "apecloud-mysql-cluster.replicas" . }}
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
standalone mode: 1
raftGroup mode: max(replicas, 3)
*/}}
{{- define "apecloud-mysql-cluster.replicas" }}
{{- if eq .Values.mode "standalone" }}
{{- 1 }}
{{- else if eq .Values.mode "raftGroup" }}
{{- max .Values.replicas 3 }}
{{- end }}
{{- end -}}

{{- define "apecloud-mysql-cluster.topology" }}
{{- if and (eq .Values.mode "raftGroup") .Values.proxyEnabled }}
  {{- if .Values.auditLogEnabled}}
    {{- "apecloud-mysql-audit-with-proxy" }}
  {{- else }}
    {{- "apecloud-mysql-with-proxy" }}
  {{- end }}
{{- else }}
  {{- if .Values.auditLogEnabled}}
    {{- "apecloud-mysql-auditlog" }}
  {{- else }}
    {{- "apecloud-mysql" }}
  {{- end }}
{{- end -}}
{{- end -}}

{{- define "apecloud-mysql-cluster.serviceRef" }}
- name: etcd
  namespace: {{ .Release.Namespace }}
  serviceDescriptor: {{ include "kblib.clusterName" . }}-etcd-descriptor
{{- end -}}