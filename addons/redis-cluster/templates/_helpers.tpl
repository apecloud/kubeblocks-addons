{{/*
Define common fileds of cluster object
*/}}
{{- define "redis-cluster.clusterCommonWithNodePort" }}
apiVersion: apps.kubeblocks.io/v1alpha1
kind: Cluster
metadata:
  name: {{ include "kblib.clusterName" . }}
  namespace: {{ .Release.Namespace }}
  labels: {{ include "kblib.clusterLabels" . | nindent 4 }}
  annotations:
    {{- include "redis-cluster.nodeportFeatureGate" . | nindent 4 }}
spec:
  clusterVersionRef: {{ .Values.version }}
  terminationPolicy: {{ .Values.extra.terminationPolicy }}
  {{- include "kblib.affinity" . | indent 2 }}
{{- end }}

{{/*
Define redis cluster annotation keys for nodeport feature gate.
*/}}
{{- define "redis-cluster.nodeportFeatureGate" -}}
kubeblocks.io/enabled-node-port-svc: redis,redis-sentinel
kubeblocks.io/enabled-pod-ordinal-svc: redis,redis-sentinel
{{- end }}

{{/*
Define redis cluster annotation keys for cluster mode nodeport feature gate.
*/}}
{{- define "redis-cluster.clusterNodeportFeatureGate" -}}
kubeblocks.io/enabled-node-port-svc: shard
kubeblocks.io/enabled-pod-ordinal-svc: shard
kubeblocks.io/enabled-shard-svc: shard
{{- end }}

{{/*
Define redis cluster mode shardingSpec
*/}}
{{- define "redis-cluster.shardingSpec" }}
- name: shard
  shards: {{ .Values.redisCluster.shardCount }}
  template:
    name: redis
    componentDef: redis-cluster
    replicas: {{ .Values.replicas }}
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
Define redis cluster sentinel component.
*/}}
{{- define "redis-cluster.sentinel" }}
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
Define redis cluster twemproxy component.
*/}}
{{- define "redis-cluster.twemproxy" }}
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

*/}}
{{- define "redis-cluster.sentinelCompDef" }}
- componentDef: redis-sentinel
  name: redis-sentinel
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
Define replica count.
standalone mode: 1
replication mode: 2
*/}}
{{- define "redis-cluster.replicaCount" }}
{{- if eq .Values.mode "standalone" }}
replicas: 1
{{- else if eq .Values.mode "replication" }}
replicas: {{ max .Values.replicas 2 }}
{{- end }}
{{- end }}

{{/*
Define redis cluster sharding count.
*/}}
{{- define "redis-cluster.shards" }}
shards: {{ max .Values.redisCluster.shardCount 3 }}
{{- end }}
