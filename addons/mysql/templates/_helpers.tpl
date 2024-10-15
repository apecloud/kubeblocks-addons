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
Define mysql component definition name prefix
*/}}
{{- define "mysql.cmpdNamePrefix" -}}
{{- default "mysql" .Values.cmpdNamePrefix -}}
{{- end -}}

{{/*
Define mysql orc component definition name prefix
*/}}
{{- define "mysql.cmpdOrcNamePrefix" -}}
{{ include "mysql.cmpdNamePrefix" . }}-orc
{{- end -}}

{{/*
Define mysql component definition regex regular
*/}}
{{- define "mysql.componentDefRegex" -}}
{{- printf "^%s" (include "mysql.cmpdNamePrefix" .) -}}-\d+\.\d+.*$
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefName57" -}}
{{- printf "%s-5.7-%s" (include "mysql.cmpdNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefNameOrc57" -}}
{{- printf "%s-5.7-%s" (include "mysql.cmpdOrcNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefName80" -}}
{{- printf "%s-8.0-%s" (include "mysql.cmpdNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefNameOrc80" -}}
{{- printf "%s-8.0-%s" (include "mysql.cmpdOrcNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefName84" -}}
{{- printf "%s-8.4-%s" (include "mysql.cmpdNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "proxysql.componentDefName" -}}
{{- printf "%s-proxysql-%s" (include "mysql.cmpdNamePrefix" .) .Chart.Version -}}
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
Common annotations
*/}}
{{- define "mysql.annotations" -}}
helm.sh/resource-policy: keep              
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
    periodSeconds: {{ .Values.roleProbe.periodSeconds }}
    timeoutSeconds: {{ .Values.roleProbe.timeoutSeconds }}
    exec:
      container: mysql
      command:
        - /tools/dbctl
        - --config-path
        - /tools/config/dbctl/components
        - mysql
        - getrole
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
    - /config
    - /tools/
  image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.syncer.repository }}:{{ .Values.image.syncer.tag }}
  imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
  name: init-syncer
  volumeMounts:
    - mountPath: /tools
      name: tools
- command:
    - cp
    - -r
    - /bin/dbctl
    - /config
    - /tools/
  image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.dbctl.repository }}:{{ .Values.image.dbctl.tag }}
  imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
  name: init-dbctl
  volumeMounts:
    - mountPath: /tools
      name: tools
{{- end }}

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
    mv {{ .Values.dataMountPath }}/plugin/audit_log.so /usr/lib64/mysql/plugin/
    rm -rf {{ .Values.dataMountPath }}/plugin
    chown -R mysql:root {{ .Values.dataMountPath }}
    skip_slave_start="OFF"
    if [ -f {{ .Values.dataMountPath }}/data/.restore_new_cluster ]; then
      skip_slave_start="ON"
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

