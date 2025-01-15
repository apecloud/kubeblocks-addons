{{/*
Define redis cluster shardingSpec with ComponentDefinition.
*/}}
{{- define "redis-cluster.shardingSpec" }}
- name: shard
  shards: {{ .Values.redisCluster.shardCount }}
  template:
    name: redis
    componentDef: redis-cluster-7
    replicas: {{ .Values.replicas }}
    {{- include "redis-cluster.exporter" . | indent 4 }}
    {{- if and .Values.nodePortEnabled (not .Values.hostNetworkEnabled) }}
    services:
    - name: redis-advertised
      serviceType: NodePort
      podService: true
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
  {{- if and .Values.nodePortEnabled (not .Values.hostNetworkEnabled) }}
  services:
  - name: redis-advertised
    serviceType: NodePort
    podService: true
  {{- end }}
  env:
  {{- if .Values.sentinel.customMasterName }}
  - name: CUSTOM_SENTINEL_MASTER_NAME
    value: {{ .Values.sentinel.customMasterName }}
  {{- end }}
  serviceVersion: {{ .Values.version }}
  serviceAccountName: {{ include "kblib.serviceAccountName" . }}
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
  {{- if and .Values.nodePortEnabled (not .Values.hostNetworkEnabled) }}
  services:
  - name: sentinel-advertised
    serviceType: NodePort
    podService: true
  {{- end }}
  serviceVersion: {{ .Values.version }}
  serviceAccountName: {{ include "kblib.serviceAccountName" . }}
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
        resources:
          requests:
            storage: {{ print .Values.sentinel.storage "Gi" }}
{{- end }}

{{/*
Define redis twemproxy ComponentSpec with ComponentDefinition.
*/}}
{{- define "redis-cluster.twemproxyComponentSpec" }}
- name: redis-twemproxy
  serviceAccountName: {{ include "kblib.serviceAccountName" . }}
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
Define common fileds of cluster object
*/}}
{{- define "redis-cluster.clusterCommon" }}
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: {{ include "kblib.clusterName" . }}
  namespace: {{ .Release.Namespace }}
  labels: {{ include "kblib.clusterLabels" . | nindent 4 }}
  {{- if and .Values.hostNetworkEnabled (eq .Values.mode "cluster") }}
  annotations:
    kubeblocks.io/host-network: "shard"
  {{- else if .Values.hostNetworkEnabled }}
  annotations:
    kubeblocks.io/host-network: "redis,redis-sentinel"
  {{- end }}
spec:
  terminationPolicy: {{ .Values.extra.terminationPolicy }}
{{- end }}