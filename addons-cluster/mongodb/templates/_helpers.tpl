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

{{/*
Define mongodb replicaset mode.
*/}}
{{- define "mongodb-cluster.replicasetMode" }}
componentSpecs:
  - name: mongodb
    componentDef: mongodb
    serviceVersion: {{ .Values.version }}
    {{- include "mongodb-cluster.replicaCount" . | indent 4 }}
    disableExporter: {{ $.Values.disableExporter | default "false" }}
    {{- include "kblib.componentResources" . | indent 4 }}
    {{- include "kblib.componentStorages" . | indent 4 }}
{{- end }}

{{/*
Define mongodb sharding mode.
*/}}
{{- define "mongodb-cluster.shardingMode" }}
shardings:
  - name: &sharding_name shard
    shards: {{ .Values.shards | default 3 }}
    template:
      name: *sharding_name
      serviceVersion: {{ .Values.version }}
      replicas: {{ .Values.replicas | default 3 }}
      disableExporter: {{ $.Values.disableExporter | default "false" }}
      env:
        # syncer uses this env to get sharding name
        - name: SHARDING_NAME
          value: *sharding_name
      {{- include "kblib.componentResources" . | indent 6 }}
      {{- include "kblib.componentStorages" . | indent 6 }}
componentSpecs:
  - name: config-server
    replicas: {{ .Values.configServer.replicas | default 3 }}
    disableExporter: {{ $.Values.disableExporter | default "false" }}
    systemAccounts:
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
    serviceVersion: {{ .Values.version }}
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
  - name: mongos
    replicas: {{ .Values.mongos.replicas | default 3 }}
    disableExporter: {{ $.Values.disableExporter | default "false" }}
    serviceVersion: {{ .Values.version }}
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
