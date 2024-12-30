{{/*
Expand the name of the chart.
*/}}
{{- define "wesql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "wesql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "wesql.labels" -}}
helm.sh/chart: {{ include "wesql.chart" . }}
{{ include "wesql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "wesql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wesql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "wesql.annotations" -}}
helm.sh/resource-policy: keep
{{ include "wesql.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "wesql.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1alpha1
{{- end }}

{{/*
Generate scripts configmap
*/}}
{{- define "wesql.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Backup Tool image
*/}}
{{- define "wesql.bakcupToolImage" -}}
{{ .Values.backupTool.image.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.backupTool.image.repository}}:{{ .Values.backupTool.image.tag }}
{{- end }}


{{- define "wesql.spec.common" -}}
provider: wesql.io
description: WeSQL is an innovative MySQL distribution that adopts a compute-storage separation architecture, with storage backed by S3 (and S3-compatible systems). It can run on any cloud, ensuring no vendor lock-in.
serviceKind: mysql
serviceVersion: 8.0.35
services:
  - name: default
    spec:
      ports:
        - name: wesql-server
          port: 3306
          targetPort: wesql-server
    roleSelector: leader
  - name: replication
    serviceName: replication
    spec:
      ports:
        - name: raft
          port: 13306
          targetPort: raft
    podService: true
    disableAutoProvision: true
logConfigs:
  {{- range $name,$pattern := .Values.logConfigs }}
  - name: {{ $name }}
    filePathPattern: {{ $pattern }}
  {{- end }}
scripts:
  - name: wesql-scripts
    templateRef: {{ include "wesql.cmScriptsName" . }}
    namespace: {{ .Release.Namespace }}
    volumeName: scripts
    defaultMode: 0555  # for read and execute, mysql container switched user account.
systemAccounts:
  - name: root
    initAccount: true
    passwordGenerationPolicy:
      length: 16
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
  - name: kbadmin
    statement: CREATE USER ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}'; GRANT ALL PRIVILEGES ON ${ALL_DB} TO ${KB_ACCOUNT_NAME};
    passwordGenerationPolicy: &defaultPasswordGenerationPolicy
      length: 16
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
  - name: kbdataprotection
    statement: CREATE USER ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}';GRANT RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT ON ${ALL_DB} TO ${KB_ACCOUNT_NAME}; GRANT LOCK TABLES,RELOAD,PROCESS,REPLICATION CLIENT, SUPER,SELECT,EVENT,TRIGGER,SHOW VIEW ON ${ALL_DB} TO ${KB_ACCOUNT_NAME};
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbprobe
    statement: CREATE USER ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}'; GRANT REPLICATION CLIENT, PROCESS ON ${ALL_DB} TO ${KB_ACCOUNT_NAME}; GRANT SELECT ON performance_schema.* TO ${KB_ACCOUNT_NAME};
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbmonitoring
    statement: CREATE USER ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}'; GRANT REPLICATION CLIENT, PROCESS ON ${ALL_DB} TO ${KB_ACCOUNT_NAME}; GRANT SELECT ON performance_schema.* TO ${KB_ACCOUNT_NAME};
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbreplicator
    statement: CREATE USER ${KB_ACCOUNT_NAME} IDENTIFIED BY '${KB_ACCOUNT_PASSWORD}'; GRANT REPLICATION SLAVE ON ${ALL_DB} TO ${KB_ACCOUNT_NAME} WITH GRANT OPTION;
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
roles:
  - name: leader
    serviceable: true
    writable: true
    votable: true
  - name: follower
    serviceable: true
    writable: false
    votable: true
  - name: learner
    serviceable: false
    writable: false
    votable: false
lifecycleActions:
  roleProbe:
    builtinHandler: wesql
    periodSeconds: {{ .Values.roleProbe.periodSeconds }}
    timeoutSeconds: {{ .Values.roleProbe.timeoutSeconds }}
  switchover:
    withCandidate:
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ default .Values.image.tag }}
      exec:
        command:
        - /scripts/switchover-with-candidate.sh
    withoutCandidate:
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ default .Values.image.tag }}
      exec:
        command:
        - /scripts/switchover-without-candidate.sh
    scriptSpecSelectors:
    - name: apecloud-mysql-scripts
  accountProvision:
    customHandler:
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
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
exporter:
  containerName: mysql-exporter
  scrapePath: /metrics
  scrapePort: http-metrics
serviceRefDeclarations:
  - name: etcd
    serviceRefDeclarationSpecs:
      - serviceKind: etcd
        serviceVersion: "^*"
    optional: true
vars:
  - name: MYSQL_ROOT_USER
    valueFrom:
      credentialVarRef:
        # it will match a comp in the cluster with cmpd name starting with "wesql-server"
        compDef: {{ include "wesql.cmpdNameWeSQLServerPrefix" . }}
        name: root
        optional: false
        username: Required
  - name: MYSQL_ROOT_PASSWORD
    valueFrom:
      credentialVarRef:
        compDef: {{ include "wesql.cmpdNameWeSQLServerPrefix" . }}
        name: root
        optional: false
        password: Required
  - name: REPLICATION_ENDPOINT
    valueFrom:
      serviceVarRef:
        name: replication
        optional: true
        host: Required
        loadBalancer: Required
  - name: SERVICE_ETCD_ENDPOINT
    valueFrom:
      serviceRefVarRef:
        name: etcd
        endpoint: Required
        optional: true
  - name: LOCAL_ETCD_POD_FQDN
    valueFrom:
      componentVarRef:
        compDef: {{ .Values.etcd.etcdCmpdName }}
        optional: true
        podFQDNs: Required
  - name: LOCAL_ETCD_PORT
    valueFrom:
      serviceVarRef:
        compDef: {{ .Values.etcd.etcdCmpdName }}
        name: headless
        optional: true
        port: 
          name: client
          option: Optional
  - name: MY_COMP_REPLICAS
    valueFrom:
      componentVarRef:
        optional: false
        replicas: Required
  ## the mysql primary pod name which is dynamically selected, caution to use it
  - name: SYNCER_HTTP_PORT
    value: "3601"
{{- end -}}

{{- define "wesql.spec.runtime.vtablet" -}}
ports:
  - containerPort: 15100
    name: vttabletport
  - containerPort: 16100
    name: vttabletgrpc
env:
  - name: CELL
    value: {{ .Values.wesqlscale.cell | default "zone1" | quote }}
  - name: VTTABLET_PORT
    value: "15100"
  - name: VTTABLET_GRPC_PORT
  - name: VTCTLD_HOST
    value: "$(KB_CLUSTER_NAME)-wescale-ctrl-headless"
  - name: VTCTLD_WEB_PORT
    value: "15000"
  - name: SERVICE_PORT
    value: "$(VTTABLET_PORT)"
command: ["/scripts/vttablet.sh"]
volumeMounts:
  - name: scripts
    mountPath: /scripts
  - name: mysql-scale-config
    mountPath: /conf
  - name: data
    mountPath: /vtdataroot
{{- end }}


{{- define "wesql.spec.runtime.exporter" -}}
command: [ "/scripts/exporter_start.sh" ]
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

{{- define "wesql.spec.runtime.volumes" -}}
{{- if .Values.logCollector.enabled }}
- name: log-data
  hostPath:
    path: /var/log/kubeblocks
    type: DirectoryOrCreate
{{- end }}
{{- end -}}
