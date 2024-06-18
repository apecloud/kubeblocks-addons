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
  enabledLogs:
    - running
  serviceAccountName: {{ include "kblib.serviceAccountName" . }}
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
