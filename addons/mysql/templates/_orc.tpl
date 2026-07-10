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
  - name: default
    serviceName: server
    spec:
      ports:
        - name: mysql
          port: 3306
          targetPort: mysql
  - name: mysql
    podService: true
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
  - name: mysql-orc-actions-scripts
    template: mysql-orc-actions-scripts
    namespace: {{ .Release.Namespace }}
    volumeName: orc-scripts
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
      create: CREATE USER IF NOT EXISTS ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}'; GRANT ALL PRIVILEGES ON ${ALL_DB} TO ${KB_ACCOUNT_NAME} WITH GRANT OPTION;
    passwordGenerationPolicy:
      length: 16
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
  - name: proxysql
    statement:
      create: CREATE USER IF NOT EXISTS ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}'; GRANT REPLICATION CLIENT, USAGE ON ${ALL_DB} TO ${KB_ACCOUNT_NAME};
    passwordGenerationPolicy:
      length: 16
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
tls:
  volumeName: tls
  mountPath: /etc/pki/tls
  caFile: ca.pem
  certFile: cert.pem
  keyFile: key.pem
roles:
  - name: primary
    updatePriority: 2
    participatesInQuorum: false
    isExclusive: true
  - name: secondary
    updatePriority: 1
    participatesInQuorum: false
vars:
  - name: ORC_TOPOLOGY_USER
    valueFrom:
      serviceRefVarRef:
        name: orchestrator
        username: Required
  - name: ORC_TOPOLOGY_PASSWORD
    valueFrom:
      serviceRefVarRef:
        name: orchestrator
        password: Required
  - name: CLUSTER_NAME
    valueFrom:
      clusterVarRef:
        clusterName: Required
  - name: CLUSTER_NAMESPACE
    valueFrom:
      clusterVarRef:
        namespace: Required
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
  - name: MYSQL_POD_FQDN_LIST
    valueFrom:
      componentVarRef:
        optional: false
        podNames: Required
  - name: TLS_ENABLED
    valueFrom:
      tlsVarRef:
        enabled: Optional
exporter:
  containerName: mysql-exporter
  scrapePath: /metrics
  scrapePort: http-metrics
{{- end }}


{{- define "mysql-orc.spec.lifecycle.common" }}
preTerminate:
  exec:
    command:
      - bash
      - -c
      - |
        /orc-scripts/preterminate.sh 2>> /tmp/preterminate.log
        if [ $? -ne 0 ]; then
          echo "ERROR: Failed to preterminate"
          exit 1
        fi
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
        mysql -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASSWORD} -P3306 -h127.0.0.1 -e "${statement};"
        mysql_rc=$?
        eval "$previous_state"
        exit $mysql_rc
    targetPodSelector: Role
    matchingKey: primary
roleProbe:
  periodSeconds: {{ .Values.roleProbe.orc.periodSeconds }}
  timeoutSeconds: {{ .Values.roleProbe.orc.timeoutSeconds }}
  exec:
    env:
      - name: PATH
        value: /kubeblocks/:/kubeblocks-tools/:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      - name: ORC_ROLE_PROBE_CLIENT_TIMEOUT_SECONDS
        value: "{{ .Values.roleProbe.orc.clientTimeoutSeconds }}"
    command:
      - /bin/bash
      - -c
      - |
        run_orc_role_probe() {
          if command -v timeout >/dev/null 2>&1; then
            timeout "${ORC_ROLE_PROBE_CLIENT_TIMEOUT_SECONDS}s" /kubeblocks/orchestrator-client "$@"
            return $?
          fi

          local output_file pid timer_pid rc
          output_file="/tmp/orc-role-probe-${$}-${RANDOM}.out"
          /kubeblocks/orchestrator-client "$@" > "${output_file}" &
          pid=$!
          (
            sleep "${ORC_ROLE_PROBE_CLIENT_TIMEOUT_SECONDS}"
            kill "${pid}" 2>/dev/null || true
            sleep 1
            kill -9 "${pid}" 2>/dev/null || true
          ) &
          timer_pid=$!
          wait "${pid}"
          rc=$?
          kill "${timer_pid}" 2>/dev/null || true
          cat "${output_file}" 2>/dev/null || true
          rm -f "${output_file}"
          return "${rc}"
        }

        master_info=$(run_orc_role_probe -c which-cluster-master -i "${KB_AGENT_POD_NAME}" 2>/dev/null)
        if [ $? -ne 0 ]; then
          echo -n ""
          exit 0
        fi
        if [[ -z "$master_info" ]]; then
          echo -n ""
          exit 0
        fi
        master_from_orc="${master_info%%:*}"
        if [ "$master_from_orc" == "${KB_AGENT_POD_NAME}" ]; then
          echo -n "primary"
        else
          # get list of replicas
          replicas=$(run_orc_role_probe -c which-cluster-instances -i "${master_from_orc}" 2>/dev/null)
          if [ $? -ne 0 ]; then
            echo -n ""
            exit 0
          fi
          # for each replica, check if it is a secondary
          for replica in $replicas; do
            if [ "${replica%%:*}" == "${KB_AGENT_POD_NAME}" ]; then
              echo -n "secondary"
            else
              echo -n ""
            fi
          done
        fi
memberLeave:
  exec:
    command:
      - /bin/bash
      - -c
      - |
        /orc-scripts/member-leave.sh 2>> /tmp/member-leave.log
        if [ $? -ne 0 ]; then
          echo "ERROR: Failed to member leave"
          exit 1
        fi
switchover:
  timeoutSeconds: {{ .Values.switchover.timeoutSeconds }}
  exec:
    env:
      - name: MYSQL_ORC_SWITCHOVER_CLIENT_TIMEOUT_SECONDS
        value: "{{ .Values.switchover.clientTimeoutSeconds }}"
      - name: MYSQL_ORC_SWITCHOVER_VERIFY_ATTEMPTS
        value: "{{ .Values.switchover.verifyAttempts }}"
      - name: MYSQL_ORC_SWITCHOVER_VERIFY_INTERVAL_SECONDS
        value: "{{ .Values.switchover.verifyIntervalSeconds }}"
    command:
      - /bin/sh
      - -c
      - |
        /orc-scripts/switchover.sh 2>> /tmp/switchover.log
        if [ $? -ne 0 ]; then
          echo "ERROR: Failed to switchover"
          exit 1
        fi

{{- end }}


{{- define "mysql-orc.spec.initcontainer.common"}}
- command:
    - /bin/sh
    - -c
    - |
      cp -r /usr/bin/jq /kubeblocks/jq
      cp -r /scripts/orchestrator-client /kubeblocks/orchestrator-client
      cp -r /usr/local/bin/curl /kubeblocks/curl
  imagePullPolicy: {{ default .Values.image.pullPolicy "IfNotPresent" }}
  name: init-jq
  volumeMounts:
    - mountPath: /kubeblocks
      name: kubeblocks
{{- end }}

{{- define "mysql-orc.spec.runtime.mysql" -}}
imagePullPolicy: {{ default .Values.image.pullPolicy "IfNotPresent" }}
command:
  - bash
  - -c
  - |
    source /scripts/init-mysql-instance-for-orc.sh

    cp {{ .Values.dataMountPath }}/plugin/audit_log.so /usr/lib64/mysql/plugin/
    if [ -d /etc/pki/tls ]; then
      mkdir -p {{ .Values.dataMountPath }}/tls/
      cp -L /etc/pki/tls/*.pem {{ .Values.dataMountPath }}/tls/
      chmod 600 {{ .Values.dataMountPath }}/tls/*
    fi
    chown -R mysql:root {{ .Values.dataMountPath }}
    export skip_slave_start="OFF"
    if [ -f {{ .Values.dataMountPath }}/data/.restore_new_cluster ]; then
      export skip_slave_start="ON"
    fi

    # Trap SIGTERM and SIGINT to shut down MySQL
    terminate() {
      echo "Received terminate signal, shutting down MySQL"
      if kill -0 "${MYSQL_PID}" 2>/dev/null; then
        kill "${MYSQL_PID}"
        wait "${MYSQL_PID}"
      fi
      exit 0
    }
    trap terminate SIGTERM SIGINT

    # Start MySQL in the background using the original entrypoint script.
    /scripts/mysql-entrypoint.sh &
    MYSQL_PID=$!

    wait_for_connectivity
    setup_master_slave
    echo "init mysql instance for orc completed"

    echo "Mysql wrapper script finished. Keeping mysqld running in foreground."
    # The default entrypoint will now be the main process,
    # or if it exited, we wait for the background mysqld.
    wait "${MYSQL_PID}"

volumeMounts:
  - mountPath: {{ .Values.dataMountPath }}
    name: data
  - mountPath: /etc/mysql/conf.d
    name: mysql-config
  - name: scripts
    mountPath: /scripts
  - name: orc-scripts
    mountPath: /orc-scripts
  - mountPath: /kubeblocks-tools
    name: kubeblocks
ports:
  - containerPort: 3306
    name: mysql
env:
  - name: PATH
    value: /kubeblocks/xtrabackup/bin:/kubeblocks/:/kubeblocks-tools/:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  - name: MYSQL_INITDB_SKIP_TZINFO
    value: "1"
  - name: MYSQL_ROOT_HOST
    value: {{ .Values.auth.rootHost | default "%" | quote }}
  - name: HA_COMPNENT
    value: orchestrator
  - name: SERVICE_PORT
    value: "3306"
  - name: POD_NAME
    valueFrom:
      fieldRef:
        apiVersion: v1
        fieldPath: metadata.name
  - name: POD_UID
    valueFrom:
      fieldRef:
        apiVersion: v1
        fieldPath: metadata.uid
  - name: POD_IP
    valueFrom:
      fieldRef:
        apiVersion: v1
        fieldPath: status.podIP
# write a readiness probe to check if mysql is ready
readinessProbe:
  exec:
    command:
      - /bin/bash
      - -c
      - |
        mysql -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASSWORD} -P3306 -h127.0.0.1 -e "SELECT 1;"
  initialDelaySeconds: 30
  periodSeconds: 5
  timeoutSeconds: 2
  successThreshold: 1
  failureThreshold: 3
{{- end -}}
