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
  env:
    - name: ETCDCTL_API
      value: "{{ .Values.etcd.local.etcdctlApi }}"
  {{- if eq .Values.etcd.mode "serviceRef" }}
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
  configs:
    - name: vtgate-config
      externalManaged: true
  env:
    - name: ETCDCTL_API
      value: "{{ .Values.etcd.local.etcdctlApi }}"
  {{- if eq .Values.etcd.mode "serviceRef" }}
  serviceRefs:
    {{ include "apecloud-mysql-cluster.serviceRef" . | indent 4 }}
  {{- end }}
  replicas: 1
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
  {{- if  eq .Values.etcd.mode "local" }}
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
  namespace: {{ .Values.etcd.serviceRef.namespace }}
  {{- if .Values.etcd.serviceRef.cluster }}
  clusterServiceSelector:
    cluster: {{ .Values.etcd.serviceRef.cluster.name }}
    service:
      component: {{ .Values.etcd.serviceRef.cluster.component }}
      service: {{ .Values.etcd.serviceRef.cluster.service }}
      port: {{ .Values.etcd.serviceRef.cluster.port }}
    {{- if .Values.etcd.serviceRef.cluster.credential }}
    credential:
      component: {{ .Values.etcd.serviceRef.cluster.component }}
      name: {{ .Values.etcd.serviceRef.cluster.credential }}
    {{- end }}
  {{- end }}
  serviceDescriptor: {{ .Values.etcd.serviceRef.serviceDescriptor }}
{{- end -}}

{{- define "apecloud-mysql-cluster.etcdComponents" }}
- name: etcd
  serviceVersion: {{ .Values.etcd.local.serviceVersion | default "3.5.15" | quote }}
  replicas: {{ .Values.etcd.local.replicas }}
  resources:
    requests:
      cpu: 500m
      memory: 500Mi
    limits:
      cpu: 500m
      memory: 500Mi
  volumeClaimTemplates:
    - name: data
      spec:
        storageClassName: {{ .Values.proxy.storageClassName | quote }}
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: {{ .Values.etcd.local.resources.storage }}
{{- end -}}

{{- define "apecloud-mysql-cluster.schedulingPolicy" }}
schedulingPolicy:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/instance: {{ include "kblib.clusterName" . }}
              apps.kubeblocks.io/component-name: mysql
          topologyKey: kubernetes.io/hostname
        weight: 100
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/instance: {{ include "kblib.clusterName" . }}
            apps.kubeblocks.io/component-name: mysql
        topologyKey: kubernetes.io/hostname
{{- end -}}
