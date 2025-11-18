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
Define mysql component definition regex regular
*/}}
{{- define "mysql.componentDefRegex" -}}
^mysql-\d+\.\d+.*$
{{- end -}}

{{- define "mysql.componentDefMGRRegex" -}}
^mysql-mgr-\d+\.\d+.*$
{{- end -}}

{{- define "mysql.componentDefOrcRegex" -}}
^mysql-orc-\d+\.\d+.*$
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

{{- define "mysql.componentDefNameMGR80" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
mysql-mgr-8.0
{{- else -}}
{{- printf "mysql-mgr-8.0-%s" .Values.compDefinitionVersionSuffix -}}
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

{{- define "mysql.componentDefNameMGR84" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
mysql-mgr-8.4
{{- else -}}
{{- printf "mysql-mgr-8.4-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "orchestrator.serviceRefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
orchestrator
{{- else -}}
{{- printf "orchestrator-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "proxysql.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
mysql-proxysql
{{- else -}}
{{- printf "mysql-proxysql-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "proxysql.labels" -}}
helm.sh/chart: {{ include "proxysql.chart" . }}
{{ include "proxysql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "proxysql.chart" -}}
{{- printf "%s-proxysql-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "proxysql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "proxysql.componentDefName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "mysql.imagePullPolicy" -}}
{{ default "IfNotPresent" .Values.image.pullPolicy }}
{{- end }}

{{/*
Defined the specification for the common parts of mysql in syncer mode
*/}}
{{- define "mysql.spec.common" -}}
provider: kubeblocks
serviceKind: mysql
description: mysql component definition for Kubernetes
updateStrategy: BestEffortParallel

services:
  - name: default
    roleSelector: primary
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
  - name: MYSQL_ADMIN_USER
    valueFrom:
      credentialVarRef:
        name: kbadmin
        username: Required
  - name: MYSQL_ADMIN_PASSWORD
    valueFrom:
      credentialVarRef:
        name: kbadmin
        password: Required
  - name: MYSQL_REPLICATION_USER
    valueFrom:
      credentialVarRef:
        name: kbreplicator
        username: Required
  - name: MYSQL_REPLICATION_PASSWORD
    valueFrom:
      credentialVarRef:
        name: kbreplicator
        password: Required
lifecycleActions:
  roleProbe:
    builtinHandler: mysql
    periodSeconds: {{ .Values.roleProbe.periodSeconds }}
    timeoutSeconds: {{ .Values.roleProbe.timeoutSeconds }}
  accountProvision:
    customHandler:
      container: mysql
      exec:
        command:
          - mysql
        args:
          - -u$(MYSQL_ROOT_USER)
          - -p$(MYSQL_ROOT_PASSWORD)
          - -P$(MYSQL_PORT)
          - -h$(KB_ACCOUNT_ENDPOINT)
          - -e
          - $(KB_ACCOUNT_STATEMENT)
      targetPodSelector: Role
      matchingKey: leader
roles:
  - name: primary
    serviceable: true
    writable: true
  - name: secondary
    serviceable: true
    writable: false
systemAccounts:
  - name: root
    initAccount: true
    passwordGenerationPolicy:
      length: 16
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
  - name: kbadmin
    statement: select 1;
    passwordGenerationPolicy: &defaultPasswordGenerationPolicy
      length: 16
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
  - name: kbdataprotection
    statement: CREATE USER $(USERNAME) IDENTIFIED BY '$(PASSWD)';GRANT RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT ON *.* TO $(USERNAME); GRANT LOCK TABLES,RELOAD,PROCESS,REPLICATION CLIENT, SUPER,SELECT,EVENT,TRIGGER,SHOW VIEW ON *.* TO $(USERNAME);
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbprobe
    statement: CREATE USER $(USERNAME) IDENTIFIED BY '$(PASSWD)'; GRANT REPLICATION CLIENT, PROCESS ON *.* TO $(USERNAME); GRANT SELECT ON performance_schema.* TO $(USERNAME);
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbmonitoring
    statement: CREATE USER $(USERNAME) IDENTIFIED BY '$(PASSWD)'; GRANT REPLICATION CLIENT, PROCESS ON *.* TO $(USERNAME); GRANT SELECT ON performance_schema.* TO $(USERNAME);
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbreplicator
    statement: select 1;
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
{{- end }}

{{- define "mysql.spec.runtime.common" -}}
- command:
    - cp
    - -r
    - /bin/syncer
    - /bin/syncerctl
    - /tools/
  image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.syncer.repository }}:{{ .Values.image.syncer.tag }}
  imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
  name: init-syncer
  volumeMounts:
    - mountPath: /tools
      name: tools
{{- end }}

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

{{/*
Defined the specification for the common parts of mysql in orchestrator mode
*/}}
{{- define "mysql-orc.spec.common"}}
provider: kubeblocks
description: mysql component definition for Kubernetes
serviceKind: mysql
updateStrategy: BestEffortParallel

serviceRefDeclarations:
  - name: orchestrator
    serviceRefDeclarationSpecs:
      - serviceKind: orchestrator
        serviceVersion: "^*"

services:
  - name: mysql-server
    serviceName: mysql-server
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

roles:
  - name: primary
    serviceable: true
    writable: true
  - name: secondary
    serviceable: true
    writable: false

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
  - name: ORC_ENDPOINTS
    valueFrom:
      serviceRefVarRef:
        name: orchestrator
        endpoint: Required

  - name: ORC_PORTS
    valueFrom:
      serviceRefVarRef:
        name: orchestrator
        port: Required
  - name: DATA_MOUNT
    value: {{.Values.dataMountPath}}

exporter:
  containerName: mysql-exporter
  scrapePath: /metrics
  scrapePort: http-metrics
{{- end }}


{{- define "mysql-orc.spec.lifecycle.common" }}
roleProbe:
  customHandler:
    exec:
      command:
        - /bin/bash
        - -c
        - |
          topology_info=$(/kubeblocks/orchestrator-client -c topology -i $KB_CLUSTER_NAME) || true
          if [[ $topology_info == "" ]]; then
            echo -n "secondary"
            exit 0
          fi

          first_line=$(echo "$topology_info" | head -n 1)
          cleaned_line=$(echo "$first_line" | tr -d '[]')
          old_ifs="$IFS"
          IFS=',' read -ra status_array <<< "$cleaned_line"
          IFS="$old_ifs"
          status="${status_array[1]}"
          if  [ "$status" != "ok" ]; then
            exit 0
          fi

          address_port=$(echo "$first_line" | awk '{print $1}')
          master_from_orc="${address_port%:*}"
          last_digit=${KB_POD_NAME##*-}
          self_service_name=$(echo "${KB_CLUSTER_COMP_NAME}_mysql_${last_digit}" | tr '_' '-' | tr '[:upper:]' '[:lower:]' )
          if [ "$master_from_orc" == "${self_service_name}" ]; then
            echo -n "primary"
          else
            echo -n "secondary"
          fi
memberLeave:
  customHandler:
    exec:
      command:
        - /bin/bash
        - -c
        - |
          set +e
          master_from_orc=$(/kubeblocks/orchestrator-client -c which-cluster-master -i $KB_CLUSTER_NAME)
          last_digit=${KB_LEAVE_MEMBER_POD_NAME##*-}
          self_service_name=$(echo "${KB_CLUSTER_COMP_NAME}_mysql_${last_digit}" | tr '_' '-' | tr '[:upper:]' '[:lower:]' )
          if [ "${self_service_name%%:*}" == "${master_from_orc%%:*}" ]; then
            /kubeblocks/orchestrator-client -c force-master-failover -i $KB_CLUSTER_NAME
            local timeout=30
            local start_time=$(date +%s)
            local current_time
            while true; do
              current_time=$(date +%s)
              if [ $((current_time - start_time)) -gt $timeout ]; then
                break
              fi
              master_from_orc=$(/kubeblocks/orchestrator-client -c which-cluster-master -i $KB_CLUSTER_NAME)
              if [ "${self_service_name%%:*}" != "${master_from_orc%%:*}" ]; then
                break
              fi
              sleep 1
            done
          fi
          /kubeblocks/orchestrator-client -c reset-replica -i ${self_service_name}
          /kubeblocks/orchestrator-client -c forget -i ${self_service_name}
          res=$(/kubeblocks/orchestrator-client -c which-cluster-alias -i ${self_service_name})
          local start_time=$(date +%s)
          while [ "$res" == "" ]; do
            current_time=$(date +%s)
            if [ $((current_time - start_time)) -gt $timeout ]; then
              break
            fi
            sleep 1
            res=$(/kubeblocks/orchestrator-client -c instance -i ${self_service_name})
          done
          /kubeblocks/orchestrator-client -c forget -i ${self_service_name}
{{- end }}

{{- define "mysql-orc.spec.initcontainer.common"}}
- command:
    - /bin/sh
    - -c
    - |
      cp -r /usr/bin/jq /kubeblocks/jq
      cp -r /scripts/orchestrator-client /kubeblocks/orchestrator-client
      cp -r /usr/local/bin/curl /kubeblocks/curl
  image: {{ .Values.image.registry | default "docker.io" }}/apecloud/orc-tools:1.0.2
  imagePullPolicy: {{ default .Values.image.pullPolicy "IfNotPresent" }}
  name: init-jq
  volumeMounts:
    - mountPath: /kubeblocks
      name: kubeblocks
{{- end }}

{{- define "mysql-orc.spec.runtime.mysql" -}}
imagePullPolicy: {{ default .Values.image.pullPolicy "IfNotPresent" }}
lifecycle:
  postStart:
    exec:
      command: [ "/bin/sh", "-c", "/scripts/init-mysql-instance-for-orc.sh" ]
command:
  - bash
  - -c
  - |
    cp {{ .Values.dataMountPath }}/plugin/audit_log.so /usr/lib64/mysql/plugin/
    chown -R mysql:root {{ .Values.dataMountPath }}
    export skip_slave_start="OFF"
    if [ -f {{ .Values.dataMountPath }}/data/.restore_new_cluster ]; then
      export skip_slave_start="ON"
    fi
    /scripts/mysql-entrypoint.sh
volumeMounts:
  - mountPath: {{ .Values.dataMountPath }}
    name: data
  - mountPath: /etc/mysql/conf.d
    name: mysql-config
  - name: scripts
    mountPath: /scripts
  - mountPath: /kubeblocks
    name: kubeblocks
ports:
  - containerPort: 3306
    name: mysql
env:
  - name: PATH
    value: /kubeblocks/xtrabackup/bin:/kubeblocks/:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  - name: MYSQL_INITDB_SKIP_TZINFO
    value: "1"
  - name: MYSQL_ROOT_HOST
    value: {{ .Values.auth.rootHost | default "%" | quote }}
  - name: ORC_TOPOLOGY_USER
    value: {{ .Values.orchestrator.topology.username }}
  - name: ORC_TOPOLOGY_PASSWORD
    value: {{ .Values.orchestrator.topology.password }}
  - name: HA_COMPNENT
    value: orchestrator
  - name: SERVICE_PORT
    value: "3306"
{{- end -}}

{{- define "mysql-orc.spec.runtime.exporter" -}}
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

{{/*
Generate reloader scripts configmap
*/}}
{{- define "mysql.extend.reload.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "reloader/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}