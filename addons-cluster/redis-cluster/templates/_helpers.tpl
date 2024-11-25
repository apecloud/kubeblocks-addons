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
    {{- if .Values.nodePortEnabled }}
    services:
    - name: redis-advertised
      serviceType: NodePort
      podService: true
    {{- end }}
    {{- if .Values.hostNetworkEnabled }}
    env:
    - name: HOST_NETWORK_ENABLED
      value: "true"
    {{- end }}
    systemAccounts:
    - name: default
      passwordConfig:
        length: 10
        numDigits: 5
        numSymbols: 0
        letterCase: MixedCases
        seed: {{ include "kblib.clusterName" . }}
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
  {{- if .Values.nodePortEnabled }}
  services:
  - name: redis-advertised
    serviceType: NodePort
    podService: true
  {{- end }}
  env:
  - name: CUSTOM_SENTINEL_MASTER_NAME
    value: {{ .Values.sentinel.customMasterName | default "" }}
  {{- if .Values.fixedPodIPEnabled }}
  - name: FIXED_POD_IP_ENABLED
    value: "true"
  {{- end }}
  {{- if .Values.hostNetworkEnabled }}
  - name: HOST_NETWORK_ENABLED
    value: "true"
  {{- end }}
  enabledLogs:
    - running
  serviceAccountName: {{ include "kblib.serviceAccountName" . }}
  switchPolicy:
    type: Noop
  {{- include "kblib.componentResources" . | indent 2 }}
  {{- include "kblib.componentStorages" . | indent 2 }}
{{- end }}

{{/*
Define redis sentinel ComponentSpec with ComponentDefinition.
*/}}
{{- define "redis-cluster.sentinelComponentSpec" }}
- name: redis-sentinel
  replicas: {{ .Values.sentinel.replicas }}
  {{- if .Values.nodePortEnabled }}
  services:
  - name: sentinel-advertised
    serviceType: NodePort
    podService: true
  {{- end }}
  {{- if .Values.fixedPodIPEnabled }}
  env:
  - name: FIXED_POD_IP_ENABLED
    value: "true"
  {{- end }}
  {{- if .Values.hostNetworkEnabled }}
  env:
  - name: HOST_NETWORK_ENABLED
    value: "true"
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
Define redis ComponentSpec with legacy ClusterDefinition which will be deprecated in the future.
*/}}
{{- define "redis-cluster.legacyComponentSpec" }}
- name: redis
  componentDefRef: redis # ref clusterDefinition componentDefs.name
  {{- include "kblib.componentMonitor" . | indent 2 }}
  {{- include "redis-cluster.replicaCount" . | indent 2 }}
  enabledLogs:
    - running
  serviceAccountName: {{ include "kblib.serviceAccountName" . }}
  switchPolicy:
    type: Noop
  {{- include "kblib.componentResources" . | indent 2 }}
  {{- include "kblib.componentStorages" . | indent 2 }}
  {{- include "kblib.componentServices" . | indent 2 }}

{{- if and (eq .Values.mode "replication") .Values.twemproxy.enabled }}
{{- include "redis-cluster.legacyTwemproxyComponentSpec" . }}
{{- end }}

{{- if and (eq .Values.mode "replication") .Values.sentinel.enabled }}
{{- include "redis-cluster.legacySentinelComponentSpec" . }}
{{- end }}
{{- end }}

{{/*
Define redis sentinel ComponentSpec with legacy ClusterDefinition which will be deprecated in the future.
*/}}
{{- define "redis-cluster.legacySentinelComponentSpec" }}
- name: redis-sentinel
  componentDefRef: redis-sentinel
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
Define twemproxy ComponentSpec with legacy ClusterDefinition which will be deprecated in the future.
*/}}
{{- define "redis-cluster.legacyTwemproxyComponentSpec" }}
- name: redis-twemproxy
  componentDefRef: redis-twemproxy
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
Define common fileds of cluster object
*/}}
{{- define "redis-cluster.clusterCommon" }}
apiVersion: apps.kubeblocks.io/v1alpha1
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
  {{- include "kblib.affinity" . | indent 2 }}
{{- end }}
