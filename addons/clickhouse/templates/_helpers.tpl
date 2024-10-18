{{/*
Expand the name of the chart.
*/}}
{{- define "clickhouse.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "clickhouse.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "clickhouse.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "clickhouse.labels" -}}
helm.sh/chart: {{ include "clickhouse.chart" . }}
{{ include "clickhouse.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "clickhouse.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clickhouse.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
cluster component definition, define for backward compatibility
*/}}
{{- define "clickhouse.clusterComponent" -}}
workloadType: Stateful
characterType: clickhouse
monitor:
  builtIn: false
  exporterConfig:
    scrapePath: /metrics
    scrapePort: 8001
logConfigs:
  {{- range $name, $pattern := .Values.logConfigs }}
  - name: {{ $name }}
    filePathPattern: {{ $pattern }}
  {{- end }}
configSpecs:
  - name: clickhouse-tpl
    templateRef: clickhouse-tpl
    volumeName: config
    namespace: {{ .Release.Namespace }}
  - name: clickhouse-user-tpl
    templateRef: clickhouse-user-tpl
    volumeName: user-config
    namespace: {{ .Release.Namespace }}
    constraintRef: clickhouse-constraints
service:
  ports:
    - name: http
      targetPort: http
      port: 8123
    - name: tcp
      targetPort: tcp
      port: 9000
    - name: tcp-mysql
      targetPort: tcp-mysql
      port: 9004
    - name: tcp-postgresql
      targetPort: tcp-postgresql
      port: 9005
    - name: http-intersrv
      targetPort: http-intersrv
      port: 9009
    - name: http-metrics
      targetPort: http-metrics
      port: 8001
podSpec:
  securityContext:
    fsGroup: 1001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: clickhouse
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository | default "bitnami/clickhouse" }}:{{ default .Chart.AppVersion .Values.image.tag }}
      imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        runAsNonRoot: true
        runAsUser: 1001
      env:
        - name: CLICKHOUSE_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              # notes: could also reference the secret's 'password' key,
              # just keeping the same secret keys as bitnami Clickhouse chart
              name: $(CONN_CREDENTIAL_SECRET_NAME)
              key: admin-password
              optional: false
        - name: BITNAMI_DEBUG
          value: "false"
        - name: CLICKHOUSE_HTTP_PORT
          value: "8123"
        - name: CLICKHOUSE_TCP_PORT
          value: "9000"
        - name: CLICKHOUSE_MYSQL_PORT
          value: "9004"
        - name: CLICKHOUSE_POSTGRESQL_PORT
          value: "9005"
        - name: CLICKHOUSE_INTERSERVER_HTTP_PORT
          value: "9009"
        - name: CLICKHOUSE_METRICS_PORT
          value: "8001"
        - name: CLICKHOUSE_ADMIN_USER
          valueFrom:
            secretKeyRef:
              name: $(CONN_CREDENTIAL_SECRET_NAME)
              key: username
              optional: false
        - name: CLICKHOUSE_SHARD_ID
          value: "$(KB_COMP_NAME)"
        - name: SERVICE_PORT
          value: "$(CLICKHOUSE_METRICS_PORT)"
        - name: CLICKHOUSE_REPLICA_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
      ports:
        - name: http
          containerPort: 8123
        - name: tcp
          containerPort: 9000
        - name: tcp-postgresql
          containerPort: 9005
        - name: tcp-mysql
          containerPort: 9004
        - name: http-intersrv
          containerPort: 9009
        - name: http-metrics
          containerPort: 8001
      livenessProbe:
        failureThreshold: 3
        initialDelaySeconds: 10
        periodSeconds: 10
        successThreshold: 1
        timeoutSeconds: 1
        httpGet:
          path: /ping
          port: http
      readinessProbe:
        failureThreshold: 3
        initialDelaySeconds: 10
        periodSeconds: 10
        successThreshold: 1
        timeoutSeconds: 1
        httpGet:
          path: /ping
          port: http
      volumeMounts:
        - name: data
          mountPath: /bitnami/clickhouse
        - name: config
          mountPath: /bitnami/clickhouse/etc/conf.d/default
        - name: user-config
          mountPath: /bitnami/clickhouse/etc/users.d/default
{{- end }}

{{- define "clickhouse-keeper.clusterComponent" -}}
workloadType: Stateful # Consensus
characterType: clickhouse-keeper
monitor:
  builtIn: false
  exporterConfig:
    scrapePath: /metrics
    scrapePort: 8001
logConfigs:
  {{- range $name,$pattern := .Values.logConfigs }}
  - name: {{ $name }}
    filePathPattern: {{ $pattern }}
  {{- end }}
configSpecs:
  - name: clickhouse-keeper-tpl
    templateRef: clickhouse-keeper-tpl
    volumeName: config
    namespace: {{ .Release.Namespace }}
service:
  ports:
    - name: tcp
      targetPort: tcp
      port: 2181
    - name: http-metrics
      targetPort: http-metrics
      port: 8001
podSpec:
  securityContext:
    fsGroup: 1001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: clickhouse
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository | default "bitnami/clickhouse" }}:{{ default .Chart.AppVersion .Values.image.tag }}
      imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        runAsNonRoot: true
        runAsUser: 1001
      env:
        - name: CLICKHOUSE_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: $(CONN_CREDENTIAL_SECRET_NAME)
              key: admin-password
              optional: false
        - name: BITNAMI_DEBUG
          value: "false"
        - name: CLICKHOUSE_KEEPER_TCP_PORT
          value: "2181"
        - name: CLICKHOUSE_KEEPER_RAFT_PORT
          value: "9181"
        - name: CLICKHOUSE_METRICS_PORT
          value: "8001"
        - name: SERVICE_PORT
          value: "$(CLICKHOUSE_METRICS_PORT)"
      ports:
        - name: tcp
          containerPort: 2181
        - name: raft
          containerPort: 9444
        - name: http-metrics
          containerPort: 8001
      volumeMounts:
        - name: data
          mountPath: /bitnami/clickhouse
        - name: config
          mountPath: /bitnami/clickhouse/etc/conf.d/default
{{- end }}

{{- define "zookeeper.clusterComponent" -}}
workloadType: Stateful #Consensus
characterType: zookeeper
logConfigs:
  {{- range $name,$pattern := .Values.zookeeper.logConfigs }}
  - name: {{ $name }}
    filePathPattern: {{ $pattern }}
  {{- end }}
configSpecs:
{{- if .Values.zookeeper.configuration }}
  - name: zookeeper-tpl
    templateRef: zookeeper-tpl
    namespace: {{ .Release.Namespace }}
    volumeName: config
{{- end }}
scriptSpecs:
  - name: zookeeper-scripts-tpl
    templateRef: zookeeper-scripts-tpl
    namespace: {{ .Release.Namespace }}
    volumeName: scripts
    defaultMode: 0755
service:
  ports:
    - name: tcp-client
      port: 2181
      targetPort: client
    - name: metrics
      port: 9141
      targetPort: metrics
podSpec:
  securityContext:
    fsGroup: 1001
  containers:
    - name: zookeeper
      image: {{ .Values.zookeeper.image.registry | default "docker.io" }}/{{ .Values.zookeeper.image.repository | default "bitnami/zookeeper" }}:{{ .Values.zookeeper.image.tag }}
      imagePullPolicy: {{ default "IfNotPresent" .Values.zookeeper.image.pullPolicy }}
      securityContext:
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 1001
      command:
        - /scripts/setup.sh
      env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.name
        - name: BITNAMI_DEBUG
          value: "false"
        - name: ZOO_DATA_LOG_DIR
          value: ""
        - name: ZOO_PORT_NUMBER
          value: "2181"
        - name: ZOO_TICK_TIME
          value: "2000"
        - name: ZOO_INIT_LIMIT
          value: "10"
        - name: ZOO_SYNC_LIMIT
          value: "5"
        - name: ZOO_PRE_ALLOC_SIZE
          value: "65536"
        - name: ZOO_SNAPCOUNT
          value: "100000"
        - name: ZOO_MAX_CLIENT_CNXNS
          value: "60"
        - name: ZOO_4LW_COMMANDS_WHITELIST
          value: "srvr, mntr, ruok"
        - name: ZOO_LISTEN_ALLIPS_ENABLED
          value: "no"
        - name: ZOO_AUTOPURGE_INTERVAL
          value: "0"
        - name: ZOO_AUTOPURGE_RETAIN_COUNT
          value: "3"
        - name: ZOO_MAX_SESSION_TIMEOUT
          value: "40000"
        # HACK: hack for single ZK node only
        - name: ZOO_SERVERS
          value: "$(KB_POD_NAME).$(KB_CLUSTER_COMP_NAME).$(KB_NAMESPACE).svc.cluster.local:2888:3888::1"
          # value: myck-zookeeper-0.myck-zookeeper-headless.$(POD_NAMESPACE).svc:2888:3888::1 myck-zookeeper-1.myck-zookeeper-headless.$(POD_NAMESPACE).svc:2888:3888::2 myck-zookeeper-2.myck-zookeeper-headless.$(POD_NAMESPACE).svc:2888:3888::3
        - name: ZOO_ENABLE_AUTH
          value: "no"
        - name: ZOO_ENABLE_QUORUM_AUTH
          value: "no"
        - name: ZOO_HEAP_SIZE
          value: "1024"
        - name: ZOO_LOG_LEVEL
          value: "ERROR"
        - name: ALLOW_ANONYMOUS_LOGIN
          value: "yes"
        - name: ZOO_ENABLE_PROMETHEUS_METRICS
          value: "yes"
        - name: ZOO_PROMETHEUS_METRICS_PORT_NUMBER
          value: "9141"
        - name: POD_NAME
          value: "$(KB_POD_NAME)"
        - name: POD_NAMESPACE
          value: "$(KB_NAMESPACE)"
        - name: SERVICE_PORT
          value: "$(ZOO_PROMETHEUS_METRICS_PORT_NUMBER)"
        # TODO: using componentDefRef to inject zookeeper or keeper env
      ports:
        - name: client
          containerPort: 2181
        - name: follower
          containerPort: 2888
        - name: election
          containerPort: 3888
        - name: metrics
          containerPort: 9141
      volumeMounts:
        - name: scripts
          mountPath: /scripts/setup.sh
          subPath: setup.sh
        - name: data
          mountPath: /bitnami/zookeeper
{{- end }}