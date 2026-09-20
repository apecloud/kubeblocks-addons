{{- define "valkey-cluster.tls" }}
tls: {{ .Values.tlsEnable }}
{{- if .Values.tlsEnable }}
issuer:
  name: UserProvided
  secretRef:
    name: {{ include "kblib.clusterName" . }}-tls
    namespace: {{ .Release.Namespace }}
    ca: ca.crt
    cert: tls.crt
    key: tls.key
{{- end }}
{{- end }}

{{- define "valkey-cluster.exporter" }}
{{- if or .Values.prometheus.enabled (not .Values.extra.disableExporter) }}
disableExporter: false
{{- else }}
disableExporter: true
{{- end }}
{{- end }}

{{- define "valkey-cluster.replicaCount" }}
{{- if eq .Values.mode "standalone" }}
replicas: 1
{{- else if eq .Values.mode "replication" }}
replicas: {{ max .Values.replicas 2 }}
{{- end }}
{{- end }}

{{- define "valkey-cluster.major" -}}
{{- regexFind "^[0-9]+" (toString .Values.version) -}}
{{- end -}}

{{- define "valkey-cluster.topology" -}}
{{- if eq .Values.mode "replication" -}}
{{- printf "replication-%s" (include "valkey-cluster.major" .) -}}
{{- else -}}
{{- .Values.mode -}}
{{- end -}}
{{- end -}}

{{- define "valkey-cluster.clusterCommon" }}
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: {{ include "kblib.clusterName" . }}
  namespace: {{ .Release.Namespace }}
  labels: {{ include "kblib.clusterLabels" . | nindent 4 }}
  annotations:
    apps.kubeblocks.io/mode: {{ .Values.mode }}
spec:
  terminationPolicy: {{ .Values.extra.terminationPolicy }}
  clusterDef: valkey
  topology: {{ include "valkey-cluster.topology" . }}
{{- end }}

{{- define "valkey-cluster.componentResources" }}
resources:
  limits:
    cpu: {{ .Values.cpu | quote }}
    memory: {{ print .Values.memory "Gi" | quote }}
  requests:
    cpu: {{ .Values.cpu | quote }}
    memory: {{ print .Values.memory "Gi" | quote }}
{{- end }}

{{- define "valkey-cluster.componentStorages" }}
volumeClaimTemplates:
  - name: data
    spec:
      accessModes:
        - ReadWriteOnce
      {{- if .Values.storageClassName }}
      storageClassName: {{ .Values.storageClassName | quote }}
      {{- end }}
      resources:
        requests:
          storage: {{ print .Values.storage "Gi" }}
{{- end }}

{{- define "valkey-cluster.sentinelResources" }}
resources:
  limits:
    cpu: {{ .Values.sentinel.cpu | quote }}
    memory: {{ print .Values.sentinel.memory "Gi" | quote }}
  requests:
    cpu: {{ .Values.sentinel.cpu | quote }}
    memory: {{ print .Values.sentinel.memory "Gi" | quote }}
{{- end }}

{{- define "valkey-cluster.sentinelStorages" }}
volumeClaimTemplates:
  - name: data
    spec:
      accessModes:
        - ReadWriteOnce
      {{- if .Values.sentinel.storageClassName }}
      storageClassName: {{ .Values.sentinel.storageClassName | quote }}
      {{- end }}
      resources:
        requests:
          storage: {{ print .Values.sentinel.storage "Gi" }}
{{- end }}

{{- define "valkey-cluster.componentSchedulingPolicy" }}
schedulingPolicy:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - podAffinityTerm:
            labelSelector:
              matchLabels:
                app.kubernetes.io/instance: {{ include "kblib.clusterName" . | quote }}
                app.kubernetes.io/managed-by: "kubeblocks"
                apps.kubeblocks.io/component-name: "valkey"
            topologyKey: kubernetes.io/hostname
          weight: 100
{{- end }}

{{- define "valkey-cluster.sentinelSchedulingPolicy" }}
schedulingPolicy:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - podAffinityTerm:
            labelSelector:
              matchLabels:
                app.kubernetes.io/instance: {{ include "kblib.clusterName" . | quote }}
                app.kubernetes.io/managed-by: "kubeblocks"
                apps.kubeblocks.io/component-name: "valkey-sentinel"
            topologyKey: kubernetes.io/hostname
          weight: 100
{{- end }}

{{- define "valkey-cluster.componentSpec" }}
- name: valkey
  {{- include "valkey-cluster.replicaCount" . | nindent 2 }}
  serviceVersion: {{ .Values.version | quote }}
  {{- include "valkey-cluster.exporter" . | nindent 2 }}
  {{- if .Values.podAntiAffinityEnabled }}
  {{- include "valkey-cluster.componentSchedulingPolicy" . | nindent 2 }}
  {{- end }}
  {{- if and .Values.nodePortEnabled (not .Values.loadBalancerEnabled) }}
  services:
    - name: valkey-advertised
      serviceType: NodePort
      podService: true
  {{- end }}
  {{- if and .Values.loadBalancerEnabled (not .Values.nodePortEnabled) }}
  services:
    - name: valkey-lb-advertised
      serviceType: LoadBalancer
      podService: true
      {{- include "kblib.loadBalancerAnnotations" . | nindent 6 }}
  {{- end }}
  {{- if and .Values.customSecretName .Values.customSecretNamespace }}
  systemAccounts:
    - name: default
      secretRef:
        name: {{ .Values.customSecretName }}
        namespace: {{ .Values.customSecretNamespace }}
  {{- end }}
  {{- include "valkey-cluster.componentResources" . | nindent 2 }}
  {{- include "valkey-cluster.componentStorages" . | nindent 2 }}
  {{- include "valkey-cluster.tls" . | nindent 2 }}
{{- end }}

{{- define "valkey-cluster.sentinelComponentSpec" }}
- name: valkey-sentinel
  replicas: {{ max .Values.sentinel.replicas 3 }}
  serviceVersion: {{ .Values.version | quote }}
  {{- include "valkey-cluster.tls" . | nindent 2 }}
  {{- if .Values.podAntiAffinityEnabled }}
  {{- include "valkey-cluster.sentinelSchedulingPolicy" . | nindent 2 }}
  {{- end }}
  {{- if and .Values.nodePortEnabled (not .Values.loadBalancerEnabled) }}
  services:
    - name: sentinel-advertised
      serviceType: NodePort
      podService: true
  {{- end }}
  {{- if and .Values.sentinel.customSecretName .Values.sentinel.customSecretNamespace }}
  systemAccounts:
    - name: default
      secretRef:
        name: {{ .Values.sentinel.customSecretName }}
        namespace: {{ .Values.sentinel.customSecretNamespace }}
  {{- end }}
  {{- include "valkey-cluster.sentinelResources" . | nindent 2 }}
  {{- include "valkey-cluster.sentinelStorages" . | nindent 2 }}
{{- end }}
