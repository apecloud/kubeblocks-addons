{{/*
Expand the name of the chart.
*/}}
{{- define "mysql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mysql.fullname" -}}
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
{{- define "mysql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mysql.labels" -}}
helm.sh/chart: {{ include "mysql.chart" . }}
{{ include "mysql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mysql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mysql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "mysql.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mysql.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
mysql
{{- else -}}
{{- printf "mysql-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define mysql component definition regex regular
*/}}
{{- define "mysql.componentDefRegex" -}}
^mysql-\d+\.\d+.*$
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefName57" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
mysql-5.7
{{- else -}}
{{- printf "mysql-5.7-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefNameOrc57" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
mysql-orc-5.7
{{- else -}}
{{- printf "mysql-orc-5.7-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefName80" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
mysql-8.0
{{- else -}}
{{- printf "mysql-8.0-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefNameOrc80" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
mysql-orc-8.0
{{- else -}}
{{- printf "mysql-orc-8.0-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefName84" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
mysql-8.4
{{- else -}}
{{- printf "mysql-8.4-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
apecloud-otel config
*/}}
{{- define "agamotto.config" -}}
extensions:
  memory_ballast:
    size_mib: 32

receivers:
  apecloudmysql:
    endpoint: ${env:ENDPOINT}
    username: ${env:MYSQL_USER}
    password: ${env:MYSQL_PASSWORD}
    allow_native_passwords: true
    database:
    collection_interval: 15s
    transport: tcp
  filelog/error:
    include: [/data/mysql/log/mysqld-error.log]
    include_file_name: false
    start_at: beginning
  filelog/slow:
    include: [/data/mysql/log/mysqld-slowquery.log]
    include_file_name: false
    start_at: beginning

processors:
  memory_limiter:
    limit_mib: 128
    spike_limit_mib: 32
    check_interval: 10s

exporters:
  prometheus:
    endpoint: 0.0.0.0:{{ .Values.metrics.service.port }}
    send_timestamps: false
    metric_expiration: 20s
    enable_open_metrics: false
    resource_to_telemetry_conversion:
      enabled: true
  apecloudfile/error:
    path: /var/log/kubeblocks/${env:KB_NAMESPACE}_${env:DB_TYPE}_${env:KB_CLUSTER_NAME}/${env:KB_POD_NAME}/error.log
    format: raw
    rotation:
      max_megabytes: 10
      max_days: 3
      max_backups: 1
      localtime: true
  apecloudfile/slow:
    path: /var/log/kubeblocks/${env:KB_NAMESPACE}_${env:DB_TYPE}_${env:KB_CLUSTER_NAME}/${env:KB_POD_NAME}/slow.log
    format: raw
    rotation:
      max_megabytes: 10
      max_days: 3
      max_backups: 1
      localtime: true

service:
  telemetry:
    logs:
      level: info
  extensions: [ memory_ballast ]
  pipelines:
    metrics:
      receivers: [ apecloudmysql ]
      processors: [ memory_limiter ]
      exporters: [ prometheus ]
    logs/error:
      receivers: [filelog/error]
      exporters: [apecloudfile/error]
    logs/slow:
      receivers: [filelog/slow]
      exporters: [apecloudfile/slow]
{{- end }}

{{/*
apecloud-otel config for proxy
*/}}
{{- define "proxy-monitor.config" -}}
receivers:
  prometheus:
    config:
      scrape_configs:
        - job_name: 'agamotto'
          scrape_interval: 15s
          static_configs:
            - targets: ['127.0.0.1:15100']
service:
  pipelines:
    metrics:
      receivers: [ apecloudmysql, prometheus ]
{{- end }}

{{- define "mysql.imagePullPolicy" -}}
{{ default "IfNotPresent" .Values.image.pullPolicy }}
{{- end }}

{{- define "mysql.spec.common" -}}
provider: kubeblocks
serviceKind: mysql
description: mysql component definition for Kubernetes
updateStrategy: BestEffortParallel

services:
  - name: mysql-server
    serviceName: mysql-server
    roleSelector: primary
    spec:
      ports:
        - name: mysql
          port: 3306
          targetPort: mysql
  - name: mysql
    serviceName: mysql
    podService: true
    spec:
      ports:
        - name: mysql
          port: 3306
          targetPort: mysql

scripts:
  - name: mysql-scripts
    templateRef: mysql-scripts
    namespace: {{ .Release.Namespace }}
    volumeName: scripts
    defaultMode: 0555
logConfigs:
  {{- range $name,$pattern := .Values.logConfigs }}
  - name: {{ $name }}
    filePathPattern: {{ $pattern }}
  {{- end }}
volumes:
  - name: data
    needSnapshot: true
systemAccounts:
  - name: root
    initAccount: true
    passwordGenerationPolicy:
      length: 10
      numDigits: 5
      numSymbols: 0
      letterCase: MixedCases
vars:
  - name: MYSQL_ROOT_USER
    valueFrom:
      credentialVarRef:
        name: root
        username: Required

  - name: MYSQL_ROOT_PASSWORD
    valueFrom:
      credentialVarRef:
        name: root
        password: Required
lifecycleActions:
  roleProbe:
    builtinHandler: mysql
    periodSeconds: {{ .Values.roleProbe.periodSeconds }}
    timeoutSeconds: {{ .Values.roleProbe.timeoutSeconds }}
roles:
  - name: primary
    serviceable: true
    writable: true
  - name: secondary
    serviceable: true
    writable: false
{{- end }}

{{- define "mysql.spec.runtime.common" -}}
- command:
    - cp
    - -r
    - /bin/syncer
    - /tools/
  image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.syncer.repository }}:{{ .Values.image.syncer.tag }}
  imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
  name: init-syncer
  volumeMounts:
    - mountPath: /tools
      name: tools
{{- end }}

{{- define "mysql.spec.runtime.exporter" -}}
command:
  - bash
  - -c
  - |
    mysqld_exporter --mysqld.username=${MYSQLD_EXPORTER_USER} --web.listen-address=:${EXPORTER_WEB_PORT} --log.level={{.Values.metrics.logLevel}}
env:
  - name: MYSQLD_EXPORTER_USER
    value: $(MYSQL_ROOT_USER)
  - name: MYSQLD_EXPORTER_PASSWORD
    value: $(MYSQL_ROOT_PASSWORD)
  - name: EXPORTER_WEB_PORT
    value: "{{ .Values.metrics.service.port }}"
image: {{ .Values.metrics.image.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.metrics.image.repository }}:{{ default .Values.metrics.image.tag }}
imagePullPolicy: IfNotPresent
ports:
  - name: http-metrics
    containerPort: {{ .Values.metrics.service.port }}
volumeMounts:
  - name: scripts
    mountPath: /scripts
{{- end -}}

{{- define "mysql.spec.runtime.images" -}}
init-jemalloc: {{ .Values.image.registry | default "docker.io" }}/apecloud/jemalloc:5.3.0
init-syncer: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.syncer.repository }}:{{ .Values.image.syncer.tag }}
{{- end -}}