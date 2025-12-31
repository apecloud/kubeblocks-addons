{{/*
etcd schedulingPolicy
*/}}
{{- define "etcd-cluster.schedulingPolicy" }}
schedulingPolicy:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/instance: {{ include "kblib.clusterName" . | quote }}
              app.kubernetes.io/managed-by: "kubeblocks"
              apps.kubeblocks.io/component-name: "etcd"
          topologyKey: kubernetes.io/hostname
        weight: 100
{{- end -}}

{{/*
Define "etcd-cluster.componentPeerService" to override component peer service
Primarily used for LoadBalancer service to enable multi-cluster communication
*/}}
{{- define "etcd-cluster.componentPeerService" -}}
{{- if .Values.peerService.type }}
services:
  - name: peer
    serviceType: {{ .Values.peerService.type }}
    podService: true
    {{- if and (eq .Values.peerService.type "LoadBalancer") (not (empty .Values.peerService.annotations)) }}
    annotations:  {{ .Values.peerService.annotations | toYaml | nindent 12 }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Define "etcd-cluster.clientService" to configure client service for etcd.
*/}}

{{- define "etcd-cluster.clientService" -}}
{{- if .Values.clientService.type }}
services:
  - name: client
    serviceName: etcd-client
    {{- if and (eq .Values.clientService.type "LoadBalancer") (not (empty .Values.clientService.annotations)) }}
    annotations: {{ .Values.clientService.annotations | toYaml | nindent 8 }}
    {{- end }}
    spec:
      type: {{ .Values.clientService.type }}
      ports:
        - port: {{ .Values.clientService.port }}
          targetPort: 2379
          {{- if .Values.clientService.nodePort }}
          nodePort: {{ .Values.clientService.nodePort }}
          {{- end }}
    componentSelector: etcd
    {{- if ne .Values.clientService.type "LoadBalancer" }}
    roleSelector: {{ .Values.clientService.role }}
    {{- end }}
{{- end }}
{{- end }}
