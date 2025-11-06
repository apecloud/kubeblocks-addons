{{/*
Define redis cluster shardingSpec with ComponentDefinition.
*/}}
{{- define "redis-cluster.shardingSpec" }}
- name: shard
  shards: {{ .Values.redisCluster.shardCount }}
  template:
    name: redis
    componentDef: redis-cluster
    replicas: {{ .Values.replicas }}
    {{- if .Values.podAntiAffinityEnabled }}
    {{- include "redis-cluster.shardingSchedulingPolicy" . | indent 2 }}
    {{- end }}
    {{- include "redis-cluster.exporter" . | indent 4 }}
    {{- if and .Values.nodePortEnabled (not .Values.hostNetworkEnabled)  (not .Values.fixedPodIPEnabled) (not .Values.loadBalancerEnabled) }}
    services:
    - name: redis-advertised
      serviceType: NodePort
      podService: true
    {{- end }}
    {{- if and .Values.loadBalancerEnabled (not .Values.fixedPodIPEnabled) (not .Values.hostNetworkEnabled) (not .Values.nodePortEnabled) }}
    services:
    - name: redis-lb-advertised
      serviceType: LoadBalancer
      podService: true
      {{- include "kblib.loadBalancerAnnotations" . | indent 4 }}
    env:
    - name: LOAD_BALANCER_ENABLED
      value: "true"
    {{- end }}
    {{- if and .Values.fixedPodIPEnabled (not .Values.nodePortEnabled) (not .Values.hostNetworkEnabled) (not .Values.loadBalancerEnabled) }}
    env:
      - name: FIXED_POD_IP_ENABLED
        value: "true"
    {{- end }}
    serviceVersion: {{ .Values.version }}
    systemAccounts:
    - name: default
      {{- if and .Values.redisCluster.customSecretName .Values.redisCluster.customSecretNamespace }}
      secretRef:
        name: {{ .Values.redisCluster.customSecretName }}
        namespace: {{ .Values.redisCluster.customSecretNamespace }}
      {{- else }}
      passwordConfig:
        length: 10
        numDigits: 5
        numSymbols: 0
        letterCase: MixedCases
        seed: {{ include "kblib.clusterName" . }}
      {{- end }}
    resources:
      limits:
        cpu: {{ .Values.cpu | quote }}
        memory:  {{ print .Values.memory "Gi" | quote }}
      requests:
        cpu: {{ .Values.cpu | quote }}
        memory:  {{ print .Values.memory "Gi" | quote }}
    volumeClaimTemplates:
      - name: data
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: {{ print .Values.storage "Gi" }}
{{- end }}

{{/*
Define redis ComponentSpec with ComponentDefinition.
*/}}
{{- define "redis-cluster.componentSpec" }}
- name: redis
  {{- include "redis-cluster.replicaCount" . | indent 2 }}
  {{- include "redis-cluster.exporter" . | indent 2 }}
  {{- if .Values.podAntiAffinityEnabled }}
  {{- include "redis-cluster.schedulingPolicy" . | indent 2 }}
  {{- end }}
  {{- if and .Values.nodePortEnabled (not .Values.hostNetworkEnabled) (not .Values.fixedPodIPEnabled) (not .Values.loadBalancerEnabled)}}
  services:
  - name: redis-advertised
    serviceType: NodePort
    podService: true
  {{- end }}
  {{- if and .Values.loadBalancerEnabled (not .Values.fixedPodIPEnabled) (not .Values.hostNetworkEnabled) (not .Values.nodePortEnabled) }}
  services:
  - name: redis-lb-advertised
    serviceType: LoadBalancer
    podService: true
    {{- include "kblib.loadBalancerAnnotations" . | indent 4 }}
  {{- end }}
  env:
  {{- if .Values.sentinel.customMasterName }}
  - name: CUSTOM_SENTINEL_MASTER_NAME
    value: {{ .Values.sentinel.customMasterName }}
  {{- end }}
  {{- if and .Values.fixedPodIPEnabled (not .Values.nodePortEnabled) (not .Values.hostNetworkEnabled) (not .Values.loadBalancerEnabled) }}
  - name: FIXED_POD_IP_ENABLED
    value: "true"
  {{- end }}
  {{- if and .Values.loadBalancerEnabled (not .Values.fixedPodIPEnabled) (not .Values.hostNetworkEnabled) (not .Values.nodePortEnabled) }}
  - name: LOAD_BALANCER_ENABLED
    value: "true"
  {{- end }}
  serviceVersion: {{ .Values.version }}
  {{- if and .Values.customSecretName .Values.customSecretNamespace }}
  systemAccounts:
    - name: default
      secretRef:
        name: {{ .Values.customSecretName }}
        namespace: {{ .Values.customSecretNamespace }}
  {{- end }}
  {{- include "kblib.componentResources" . | indent 2 }}
  {{- include "kblib.componentStorages" . | indent 2 }}
{{- end }}

{{/*
Define redis sentinel ComponentSpec with ComponentDefinition.
*/}}
{{- define "redis-cluster.sentinelComponentSpec" }}
- name: redis-sentinel
  replicas: {{ .Values.sentinel.replicas }}
  {{- if .Values.podAntiAffinityEnabled }}
  {{- include "redis-cluster.sentinelschedulingPolicy" . | indent 2 }}
  {{- end }}
  {{- if and .Values.nodePortEnabled (not .Values.hostNetworkEnabled) (not .Values.fixedPodIPEnabled) (not .Values.loadBalancerEnabled)  }}
  services:
  - name: sentinel-advertised
    serviceType: NodePort
    podService: true
  {{- end }}
  {{- if and .Values.fixedPodIPEnabled (not .Values.nodePortEnabled) (not .Values.hostNetworkEnabled) (not .Values.loadBalancerEnabled)  }}
  env:
  - name: FIXED_POD_IP_ENABLED
    value: "true"
  {{- end }}
  {{- if and .Values.loadBalancerEnabled (not .Values.fixedPodIPEnabled) (not .Values.hostNetworkEnabled) (not .Values.nodePortEnabled) (hasPrefix "5." .Values.version) }}
  services:
  - name: sentinel-lb-advertised
    serviceType: LoadBalancer
    podService: true
    {{- include "kblib.loadBalancerAnnotations" . | indent 4 }}
  env:
  - name: LOAD_BALANCER_ENABLED
    value: "true"
  {{- end }}
  serviceVersion: {{ .Values.version }}
  {{- if and .Values.sentinel.customSecretName .Values.sentinel.customSecretNamespace }}
  systemAccounts:
    - name: default
      secretRef:
        name: {{ .Values.sentinel.customSecretName }}
        namespace: {{ .Values.sentinel.customSecretNamespace }}
  {{- end }}
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
        storageClassName: {{ .Values.sentinel.storageClassName }}
        resources:
          requests:
            storage: {{ print .Values.sentinel.storage "Gi" }}
{{- end }}

{{/*
Define redis twemproxy ComponentSpec with ComponentDefinition.
*/}}
{{- define "redis-cluster.twemproxyComponentSpec" }}
- name: redis-twemproxy
  replicas: {{ .Values.twemproxy.replicas }}
  resources:
    limits:
      cpu: {{ .Values.twemproxy.cpu | quote }}
      memory: {{ print .Values.twemproxy.memory "Gi" | quote }}
    requests:
      cpu: {{ .Values.twemproxy.cpu | quote }}
      memory: {{ print .Values.twemproxy.memory "Gi" | quote }}
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
{{- else if eq .Values.mode "replication-twemproxy" }}
replicas: {{ max .Values.replicas 2 }}
{{- end }}
{{- end }}

{{/*
Define redis cluster sharding count.
*/}}
{{- define "redis-cluster.shards" }}
shards: {{ max .Values.redisCluster.shardCount 3 }}
{{- end }}


{{/*
Define redis cluster prometheus exporter.
*/}}
{{- define "redis-cluster.exporter" }}
{{/* TODO(zhangtao): Hacky if hostnetwork is enabled, the disableExporter should be false */}}
{{- if or .Values.prometheus.enabled ( not .Values.extra.disableExporter ) ( .Values.hostNetworkEnabled ) }}
disableExporter: false
{{- else }}
disableExporter: true
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "redis-cluster.selectorLabels" -}}
app.kubernetes.io/instance: {{ include "kblib.clusterName" . | quote }}
app.kubernetes.io/managed-by: "kubeblocks"
apps.kubeblocks.io/component-name: "redis"
{{- end }}

{{/*
Redis Cluster sharding schedulingPolicy
*/}}
{{- define "redis-cluster.shardingSchedulingPolicy" }}
schedulingPolicy:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/instance: {{ include "kblib.clusterName" . | quote }}
              app.kubernetes.io/managed-by: "kubeblocks"
              kubeblocks.io/role: primary
          topologyKey: kubernetes.io/hostname
        weight: 100
{{- end -}}


{{/*
Redis schedulingPolicy
*/}}
{{- define "redis-cluster.schedulingPolicy" }}
schedulingPolicy:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/instance: {{ include "kblib.clusterName" . | quote }}
              app.kubernetes.io/managed-by: "kubeblocks"
              apps.kubeblocks.io/component-name: "redis"
          topologyKey: kubernetes.io/hostname
        weight: 100
{{- end -}}

{{/*
Redis sentinel schedulingPolicy
*/}}
{{- define "redis-cluster.sentinelschedulingPolicy" }}
schedulingPolicy:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/instance: {{ include "kblib.clusterName" . | quote }}
              app.kubernetes.io/managed-by: "kubeblocks"
              apps.kubeblocks.io/component-name: "redis-sentinel"
          topologyKey: kubernetes.io/hostname
        weight: 100
{{- end -}}

{{/*
Define common fileds of cluster object
*/}}
{{- define "redis-cluster.clusterCommon" }}
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: {{ include "kblib.clusterName" . }}
  namespace: {{ .Release.Namespace }}
  labels: {{ include "kblib.clusterLabels" . | nindent 4 }}
  annotations:
    apps.kubeblocks.io/mode: {{ .Values.mode }}
  {{- if and .Values.hostNetworkEnabled (eq .Values.mode "cluster") }}
    kubeblocks.io/host-network: "shard"
  {{- else if .Values.hostNetworkEnabled }}
    kubeblocks.io/host-network: "redis,redis-sentinel"
  {{- end }}
  {{- if and .Values.podAntiAffinityEnabled (eq .Values.mode "cluster") }}
    apps.kubeblocks.io/shard-pod-anti-affinity: "shard"
  {{- end }}
spec:
  terminationPolicy: {{ .Values.extra.terminationPolicy }}
{{- end }}