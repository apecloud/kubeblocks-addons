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
  - name: proxysql
    statement:
      create: CREATE USER ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}'; GRANT REPLICATION CLIENT, USAGE ON ${ALL_DB} TO ${KB_ACCOUNT_NAME};
    passwordGenerationPolicy:
      length: 16
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
  - name: repl
    statement:
      create: CREATE USER ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}'; GRANT REPLICATION SLAVE, REPLICATION CLIENT ON ${ALL_DB} TO ${KB_ACCOUNT_NAME} WITH GRANT OPTION;
    passwordGenerationPolicy:
      length: 10
      numDigits: 5
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
  - name: MYSQL_REPLICATION_USER
    valueFrom:
      credentialVarRef:
        name: repl
        username: Required
  - name: MYSQL_REPLICATION_PASSWORD
    valueFrom:
      credentialVarRef:
        name: repl
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
postProvision:
  exec:
    container: mysql
    command:
      - bash
      - -c
      - "/scripts/mysql-orchestrator-register.sh"
  preCondition: RuntimeReady
preTerminate:
  exec:
    command:
      - bash
      - -c
      - curl http://${ORC_ENDPOINTS%%:*}:${ORC_PORTS}/api/forget-cluster/${CLUSTER_NAME}.${CLUSTER_NAMESPACE} || true
accountProvision:
  exec:
    container: mysql
    command:
      - bash
      - -c
      - |
        set -ex
        ALL_DB='*.*'
        eval statement=\"${KB_ACCOUNT_STATEMENT}\"
        mysql -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASSWORD} -P3306 -h127.0.0.1 -e "${statement};FLUSH PRIVILEGES;"
    targetPodSelector: Role
    matchingKey: primary
roleProbe:
  periodSeconds: {{ .Values.roleProbe.periodSeconds }}
  timeoutSeconds: {{ .Values.roleProbe.timeoutSeconds }}
  exec:
    env:
      - name: PATH
        value: /kubeblocks/:/kubeblocks-tools/:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    command:
      - /bin/bash
      - -c
      - |
        topology_info=$(/kubeblocks/orchestrator-client -c topology -i ${CLUSTER_NAME}) || true
        if [[ $topology_info == "" ]]; then
          echo -n "secondary"
          exit 0
        fi

        first_line=$(echo "$topology_info" | head -n 1)
        cleaned_line=$(echo "$first_line" | tr -d '[]')
        IFS=',' read -ra status_array <<< "$cleaned_line"
        status="${status_array[1]}"
        if  [ "$status" != "ok" ]; then
          exit 0
        fi

        address_port=$(echo "$first_line" | awk '{print $1}')
        master_from_orc="${address_port%:*}"
        self_service_name=$(echo "${KB_AGENT_POD_NAME}" | tr '_' '-' | tr '[:upper:]' '[:lower:]' )
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
        /orc-scripts/member-leave.sh >> /tmp/member-leave.log 2>&1

switchover:
  exec:
    command:
      - /bin/sh
      - -c
      - |
        /orc-scripts/switchover.sh  >> /tmp/switchover.log 2>&1

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
lifecycle:
  postStart:
    exec:
      command: [ "/bin/sh", "-c", "/scripts/init-mysql-instance-for-orc.sh" ]
command:
  - bash
  - -c
  - |
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
    /scripts/mysql-entrypoint.sh
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
{{- end -}}
