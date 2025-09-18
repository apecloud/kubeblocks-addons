{{/*
Define falkordb cluster shardingSpec with ComponentDefinition.
*/}}
{{- define "falkordb-cluster.shardingSpec" }}
- name: shard
  shards: {{ .Values.falkordbCluster.shardCount }}
  template:
    name: falkordb
    componentDef: falkordb-cluster
    replicas: {{ .Values.replicas }}
    {{- if .Values.podAntiAffinityEnabled }}
    {{- include "falkordb-cluster.shardingSchedulingPolicy" . | indent 2 }}
    {{- end }}
    {{- include "falkordb-cluster.exporter" . | indent 4 }}
    {{- if and .Values.nodePortEnabled (not .Values.hostNetworkEnabled)  (not .Values.fixedPodIPEnabled) (not .Values.loadBalancerEnabled) }}
    services:
    - name: falkordb-advertised
      serviceType: NodePort
      podService: true
    {{- end }}
    {{- if and .Values.loadBalancerEnabled (not .Values.fixedPodIPEnabled) (not .Values.hostNetworkEnabled) (not .Values.nodePortEnabled) }}
    services:
    - name: falkordb-lb-advertised
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
      {{- if and .Values.falkordbCluster.customSecretName .Values.falkordbCluster.customSecretNamespace }}
      secretRef:
        name: {{ .Values.falkordbCluster.customSecretName }}
        namespace: {{ .Values.falkordbCluster.customSecretNamespace }}
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
Define falkordb ComponentSpec with ComponentDefinition.
*/}}
{{- define "falkordb-cluster.componentSpec" }}
- name: falkordb
  {{- include "falkordb-cluster.replicaCount" . | indent 2 }}
  {{- include "falkordb-cluster.exporter" . | indent 2 }}
  {{- if .Values.podAntiAffinityEnabled }}
  {{- include "falkordb-cluster.schedulingPolicy" . | indent 2 }}
  {{- end }}
  {{- if and .Values.nodePortEnabled (not .Values.hostNetworkEnabled) (not .Values.fixedPodIPEnabled) (not .Values.loadBalancerEnabled)}}
  services:
  - name: falkordb-advertised
    serviceType: NodePort
    podService: true
  {{- end }}
  {{- if and .Values.loadBalancerEnabled (not .Values.fixedPodIPEnabled) (not .Values.hostNetworkEnabled) (not .Values.nodePortEnabled) }}
  services:
  - name: falkordb-lb-advertised
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
Define falkordb sentinel ComponentSpec with ComponentDefinition.
*/}}
{{- define "falkordb-cluster.sentinelComponentSpec" }}
- name: falkordb-sent
  replicas: {{ .Values.sentinel.replicas }}
  {{- if .Values.podAntiAffinityEnabled }}
  {{- include "falkordb-cluster.sentinelschedulingPolicy" . | indent 2 }}
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
Define replica count.
standalone mode: 1
replication mode: 2
*/}}
{{- define "falkordb-cluster.replicaCount" }}
{{- if eq .Values.mode "standalone" }}
replicas: 1
{{- else if eq .Values.mode "replication" }}
replicas: {{ max .Values.replicas 2 }}
{{- else if eq .Values.mode "replication-twemproxy" }}
replicas: {{ max .Values.replicas 2 }}
{{- end }}
{{- end }}

{{/*
Define falkordb cluster sharding count.
*/}}
{{- define "falkordb-cluster.shards" }}
shards: {{ max .Values.falkordbCluster.shardCount 3 }}
{{- end }}


{{/*
Define falkordb cluster prometheus exporter.
*/}}
{{- define "falkordb-cluster.exporter" }}
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
{{- define "falkordb-cluster.selectorLabels" -}}
app.kubernetes.io/instance: {{ include "kblib.clusterName" . | quote }}
app.kubernetes.io/managed-by: "kubeblocks"
apps.kubeblocks.io/component-name: "falkordb"
{{- end }}

{{/*
falkordb Cluster sharding schedulingPolicy
*/}}
{{- define "falkordb-cluster.shardingSchedulingPolicy" }}
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
falkordb schedulingPolicy
*/}}
{{- define "falkordb-cluster.schedulingPolicy" }}
schedulingPolicy:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/instance: {{ include "kblib.clusterName" . | quote }}
              app.kubernetes.io/managed-by: "kubeblocks"
              apps.kubeblocks.io/component-name: "falkordb"
          topologyKey: kubernetes.io/hostname
        weight: 100
{{- end -}}

{{/*
falkordb sentinel schedulingPolicy
*/}}
{{- define "falkordb-cluster.sentinelschedulingPolicy" }}
schedulingPolicy:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/instance: {{ include "kblib.clusterName" . | quote }}
              app.kubernetes.io/managed-by: "kubeblocks"
              apps.kubeblocks.io/component-name: "falkordb-sent"
          topologyKey: kubernetes.io/hostname
        weight: 100
{{- end -}}

{{/*
Define common fileds of cluster object
*/}}
{{- define "falkordb-cluster.clusterCommon" }}
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
    kubeblocks.io/host-network: "falkordb,falkordb-sent"
  {{- end }}
  {{- if and .Values.podAntiAffinityEnabled (eq .Values.mode "cluster") }}
    apps.kubeblocks.io/shard-pod-anti-affinity: "shard"
  {{- end }}
spec:
  terminationPolicy: {{ .Values.extra.terminationPolicy }}
{{- end }}