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
    serviceName: client
    {{- if and (eq .Values.clientService.type "LoadBalancer") (not (empty .Values.clientService.annotations)) }}
    annotations: {{ .Values.clientService.annotations | toYaml | nindent 8 }}
    {{- end }}
    spec:
      type: {{ .Values.clientService.type }}
      ports:
        - port: {{ .Values.clientService.port }}
          targetPort: 2379
    componentSelector: etcd
    {{- if ne .Values.clientService.type "LoadBalancer" }}
    roleSelector: {{ .Values.clientService.role }}
    {{- end }}
{{- end }}
{{- end }}