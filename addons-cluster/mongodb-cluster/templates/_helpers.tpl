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
Define mongodb replicaset mode.
*/}}
{{- define "mongodb-cluster.replicasetMode" }}
{{- if .Values.useLegacyCompDef }}
clusterDefinitionRef: mongodb
{{- end }}
componentSpecs:
  - name: mongodb
    {{- if .Values.useLegacyCompDef }}
    componentDefRef: {{ include "mongodb-cluster.componentDefRef" $}}
    {{- else }}
    componentDef: mongodb
    serviceVersion: {{ .Values.version }}
    {{- end }}
    {{- include "mongodb-cluster.replicaCount" . | indent 4 }}
    disableExporter: {{ $.Values.disableExporter | default "false" }}
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
  - name: &sharding_name mongo-shard
    shards: {{ .Values.shards | default 3 }}
    template:
      name: *sharding_name
      componentDef: mongo-shard
      serviceVersion: {{ .Values.version }}
      replicas: {{ .Values.replicas | default 3 }}
      disableExporter: {{ $.Values.disableExporter | default "false" }}
      systemAccounts: &adminAccounts
        - name: root
          {{- if and .Values.customSecretName .Values.customSecretNamespace }}
          secretRef:
            name: {{ .Values.customSecretName }}
            namespace: {{ .Values.customSecretNamespace }}
          {{- else }}
          passwordConfig:
            length: 16
            numDigits: 8
            numSymbols: 0
            letterCase: MixedCases
            seed: {{ include "kblib.clusterName" . }}
          {{- end }}
      env:
        # syncer uses this env to get sharding name
        - name: KB_SHARDING_NAME
          value: *sharding_name
      serviceAccountName: {{ include "kblib.serviceAccountName" . }}
      {{- include "kblib.componentResources" . | indent 6 }}
      {{- include "kblib.componentStorages" . | indent 6 }}
componentSpecs:
  - name: mongo-config-server
    componentDef: mongo-config-server
    replicas: {{ .Values.configServer.replicas | default 3 }}
    disableExporter: {{ $.Values.disableExporter | default "false" }}
    systemAccounts: *adminAccounts
    serviceVersion: {{ .Values.version }}
    serviceAccountName: {{ include "kblib.serviceAccountName" . }}
    env:
      - name: MONGODB_BALANCER_ENABLED
        value: "{{ .Values.balancer.enabled }}"
    {{- with .Values.configServer.tolerations }}
    tolerations: {{ .| toYaml | nindent 6 }}
    {{- end }}
    resources:
      limits:
        cpu: {{ .Values.configServer.cpu | quote }}
        memory: {{ print .Values.configServer.memory "Gi" | quote }}
      requests:
        cpu: {{ .Values.configServer.cpu | quote }}
        memory: {{ print .Values.configServer.memory "Gi" | quote }}
    volumeClaimTemplates:
      - name: data
        spec:
          {{- if .Values.configServer.storageClassName }}
          storageClassName: {{ .Values.configServer.storageClassName | quote }}
          {{- end }}
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: {{ print .Values.configServer.storage "Gi" }}
  - name: mongo-mongos
    componentDef: mongo-mongos
    replicas: {{ .Values.mongos.replicas | default 3 }}
    disableExporter: {{ $.Values.disableExporter | default "false" }}
    serviceVersion: {{ .Values.version }}
    serviceAccountName: {{ include "kblib.serviceAccountName" . }}
    env:
      - name: MONGODB_BALANCER_ENABLED
        value: "{{ .Values.balancer.enabled }}"
    {{- with .Values.mongos.tolerations }}
    tolerations: {{ .| toYaml | nindent 6 }}
    {{- end }}
    resources:
      limits:
        cpu: {{ .Values.mongos.cpu | quote }}
        memory: {{ print .Values.mongos.memory "Gi" | quote }}
      requests:
        cpu: {{ .Values.mongos.cpu | quote }}
        memory: {{ print .Values.mongos.memory "Gi" | quote }}
{{- end }}
