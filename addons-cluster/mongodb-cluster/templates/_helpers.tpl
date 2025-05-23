{{/*
Define replica count.
standalone mode: 1
replicaset mode: 3
*/}}

{{- define "mongodb-cluster.replicaCount" }}
{{- if eq .Values.mode "standalone" }}
replicas: 1
{{- else if eq .Values.mode "replicaset" }}
replicas: {{ max .Values.replicas 3 }}
{{- end }}
{{- end }}

{{- define "mongodb-cluster.componentDefRef" }}
{{- if eq .Values.hostnetwork "enabled" }}
  {{- "mongodb-hostnetwork" | quote}}
{{- else }}
  {{- "mongodb" | quote}}
{{- end -}}
{{- end }}

{{/*
Define mongodb keyfile secret name.
*/}}
{{- define "mongodb-cluster.keyfileSecretName" }}
{{- printf "%s-mongodb-keyfile" (include "kblib.clusterName" .) }}
{{- end }}

{{/*
Define mongodb keyfile volume.
*/}}
{{- define "mongodb-cluster.keyfileVolume" }}
volumes:
  - name: mongodb-keyfile
    secret:
      secretName: {{ include "mongodb-cluster.keyfileSecretName" . }}
      defaultMode: 0400
      optional: false
{{- end }}

{{/*
Define mongodb replicaset mode.
*/}}
{{- define "mongodb-cluster.replicasetMode" }}
clusterDefinitionRef: mongodb
topology: replicaset
componentSpecs:
  - name: mongodb
    {{- if .Values.useLegacyCompDef }}
    componentDefRef: {{ include "mongodb-cluster.componentDefRef" $}}
    {{- else }}
    componentDef: mongodb
    serviceVersion: {{ .Values.version }}
    {{- end }}
    {{- include "mongodb-cluster.replicaCount" . | indent 4 }}
    serviceAccountName: {{ include "kblib.serviceAccountName" . }}
    {{- include "kblib.componentResources" . | indent 4 }}
    {{- include "kblib.componentStorages" . | indent 4 }}
    {{- include "kblib.componentServices" . | indent 4 }}
{{- end }}

{{/*
Define mongodb sharding mode.
*/}}
{{- define "mongodb-cluster.shardingMode" }}
shardingSpecs:
  - name: mongodb-shard
    shards: {{ .Values.shards | default 3 }}
    template:
      name: &sharding_name mongodb-shard
      componentDef: mongodb-shard
      # serviceVersion: {{ .Values.version }}
      replicas: {{ .Values.replicas | default 3 }}
      env:
        # syncer uses this env to get sharding name
        - name: KB_SHARDING_NAME
          value: *sharding_name
      serviceAccountName: {{ include "kblib.serviceAccountName" . }}
      {{- include "kblib.componentResources" . | indent 6 }}
      {{- include "kblib.componentStorages" . | indent 6 }}
      {{- include "mongodb-cluster.keyfileVolume" . | indent 6 }}
componentSpecs:
  - name: cfg-server
    componentDef: mongodb-cfg-server
    replicas: {{ .Values.cfgServerReplicas | default 3 }}
    # serviceVersion: {{ .Values.version }}
    serviceAccountName: {{ include "kblib.serviceAccountName" . }}
    {{- include "kblib.componentResources" . | indent 4 }}
    {{- include "kblib.componentStorages" . | indent 4 }}
    {{- include "mongodb-cluster.keyfileVolume" . | indent 4 }}
  - name: mongos
    componentDef: mongodb-mongos
    replicas: {{ .Values.mongosReplicas | default 3 }}
    # serviceVersion: {{ .Values.version }}
    serviceAccountName: {{ include "kblib.serviceAccountName" . }}
    {{- include "kblib.componentResources" . | indent 4 }}
    {{- include "kblib.componentServices" . | indent 4 }}
    {{- include "mongodb-cluster.keyfileVolume" . | indent 4 }}
{{- end }}
