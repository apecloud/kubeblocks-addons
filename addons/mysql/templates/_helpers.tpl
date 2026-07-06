{{/*
Expand the name of the chart.
*/}}
{{- define "mysql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
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
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "mysql.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "mysql.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{- define "mysql.spec.common" -}}
provider: kubeblocks
serviceKind: mysql
description: mysql component definition for Kubernetes
updateStrategy: BestEffortParallel
podManagementPolicy: Parallel
exporter:
  containerName: mysql-exporter
  scrapePath: /metrics
  scrapePort: http-metrics
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
    template: mysql-scripts
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
  - name: kbadmin
    statement:
      create: select 1;
    passwordGenerationPolicy: &defaultPasswordGenerationPolicy
      length: 16
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
  - name: kbdataprotection
    statement:
      create: CREATE USER ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}';GRANT RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT ON ${ALL_DB} TO ${KB_ACCOUNT_NAME}; GRANT LOCK TABLES,RELOAD,PROCESS,REPLICATION CLIENT, SUPER,SELECT,EVENT,TRIGGER,SHOW VIEW ON ${ALL_DB} TO ${KB_ACCOUNT_NAME};
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbprobe
    statement:
      create: CREATE USER ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}'; GRANT REPLICATION CLIENT, PROCESS ON ${ALL_DB} TO ${KB_ACCOUNT_NAME}; GRANT SELECT ON performance_schema.* TO ${KB_ACCOUNT_NAME};
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbmonitoring
    statement:
      create: CREATE USER ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}'; GRANT REPLICATION CLIENT, PROCESS ON ${ALL_DB} TO ${KB_ACCOUNT_NAME}; GRANT SELECT ON performance_schema.* TO ${KB_ACCOUNT_NAME};
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbreplicator
    statement:
      create: select 1;
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: proxysql
    statement:
      create: CREATE USER ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}'; GRANT REPLICATION CLIENT, USAGE ON ${ALL_DB} TO ${KB_ACCOUNT_NAME};
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
vars:
  - name: CLUSTER_NAME
    valueFrom:
      clusterVarRef:
        clusterName: Required
  - name: CLUSTER_UUID
    valueFrom:
      clusterVarRef:
        clusterUID: Required
  - name: CLUSTER_NAMESPACE
    valueFrom:
      clusterVarRef:
        namespace: Required
  - name: COMPONENT_NAME
    valueFrom:
      componentVarRef:
        optional: false
        shortName: Required
  - name: CLUSTER_COMPONENT_NAME
    valueFrom:
      componentVarRef:
        optional: false
        componentName: Required
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
  - name: TLS_ENABLED
    valueFrom:
      tlsVarRef:
        enabled: Optional
lifecycleActions:
  accountProvision:
    exec:
      container: mysql
      command:
        - bash
        - -c
        - |
          set -ex
          ALL_DB='*.*'
          # Suppress xtrace AND errexit so the password-bearing expansion is not echoed
          # to pod stderr. KB_ACCOUNT_STATEMENT itself contains CREATE USER ... IDENTIFIED
          # BY '<password>' (account password), and the mysql -p${MYSQL_ROOT_PASSWORD}
          # invocation contains the root password; both would land in `kubectl logs` if
          # xtrace stayed on. errexit is suppressed too so accountProvision failure can be
          # captured explicitly via $? -- if it stayed on, set -e would exit before the
          # rc-save line on any non-zero result.
          { previous_state=$(set +o); set +ex; } 2>/dev/null
          eval statement=\"${KB_ACCOUNT_STATEMENT}\"
          mysql -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASSWORD} -P3306 -h127.0.0.1 -e "${statement}"
          mysql_rc=$?
          eval "$previous_state"
          exit $mysql_rc
      targetPodSelector: Role
      matchingKey: primary
  roleProbe:
    periodSeconds: {{ .Values.roleProbe.periodSeconds }}
    timeoutSeconds: {{ .Values.roleProbe.timeoutSeconds }}
    exec:
      container: mysql
      command:
        - /tools/syncerctl
        - getrole
  switchover:
    exec:
      command:
        - /bin/sh
        - -c
        - |

          if [ "$KB_SWITCHOVER_ROLE" != "primary" ]; then
              echo "switchover not triggered for primary, nothing to do, exit 0."
              exit 0
          fi

          /tools/syncerctl switchover --primary "$KB_SWITCHOVER_CURRENT_NAME" ${KB_SWITCHOVER_CANDIDATE_NAME:+--candidate "$KB_SWITCHOVER_CANDIDATE_NAME"}
tls:
  volumeName: tls
  mountPath: /etc/pki/tls
  caFile: ca.pem
  certFile: cert.pem
  keyFile: key.pem
{{- end }}

{{- define "mysql.spec.roles.semisync" -}}
roles:
  - name: primary
    updatePriority: 2
    participatesInQuorum: false
    isExclusive: true
  - name: secondary
    updatePriority: 1
    participatesInQuorum: false
{{- end }}

{{/*
Group Replication is a majority-based protocol: members participate in quorum
so KubeBlocks will not take down a majority at once during rolling updates,
scale-in, stop, or failure recovery.
*/}}
{{- define "mysql.spec.roles.mgr" -}}
roles:
  - name: primary
    updatePriority: 2
    participatesInQuorum: true
    isExclusive: true
  - name: secondary
    updatePriority: 1
    participatesInQuorum: true
{{- end }}

{{- define "mysql.spec.runtime.entrypoint" -}}
mkdir -p {{ .Values.dataMountPath }}/{log,binlog,auditlog,temp}
if [ -f {{ .Values.dataMountPath }}/plugin/audit_log.so ]; then
  cp {{ .Values.dataMountPath }}/plugin/audit_log.so /usr/lib64/mysql/plugin/
fi
if [ -d /etc/pki/tls ]; then
  mkdir -p {{ .Values.dataMountPath }}/tls/
  cp -L /etc/pki/tls/*.pem {{ .Values.dataMountPath }}/tls/
  chmod 600 {{ .Values.dataMountPath }}/tls/*
fi
chown -R mysql:root {{ .Values.dataMountPath }}
SERVICE_ID=$((${POD_NAME##*-} + 1))
{{ end }}

{{- define "mysql.spec.runtime.common" -}}
- command:
    - cp
    - -r
    - /bin/syncer
    - /bin/syncerctl
    - /tools/
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
imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
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
mysql-exporter: {{ .Values.metrics.image.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.metrics.image.repository }}:{{ default .Values.metrics.image.tag }}
{{- end -}}

{{/*
Generate LD_PRELOAD environment variable - always set, but will be cleared at runtime for ARM64
*/}}
{{- define "mysql.spec.runtime.ldPreloadEnv" -}}
{{- if ne (.Values.architecture | default "") "arm64" }}
- name: LD_PRELOAD
  value: /tools/lib/libjemalloc.so.2
{{- end }}
{{- end -}}

{{- define "mysql.config.reconfigureAction" -}}
reconfigure:
  exec:
    container: mysql
    targetPodSelector: All
    command:
      - bash
      - -c
      - |
        set -euo pipefail

        /scripts/update-parameter.sh "$1" "$2"
      - --
{{- end -}}

{{- define "mysql.mydumper.image" -}}
{{ $registry := default ( .Values.image.registry | default "docker.io" )}}
{{- if eq $registry "docker.io" -}}
{{ $registry }}/mydumper/mydumper:{{ .Values.image.mydumper.tag }}
{{- else -}}
{{ $registry }}/apecloud/mydumper:{{ .Values.image.mydumper.tag }}
{{- end -}}
{{- end }}
