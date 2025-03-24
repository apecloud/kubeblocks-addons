{{/*
Common annotations
*/}}
{{- define "orioledb.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "orioledb.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "orioledb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Expand the name of the chart.
*/}}
{{- define "orioledb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "orioledb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "orioledb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "orioledb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "orioledb.labels" -}}
helm.sh/chart: {{ include "orioledb.chart" . }}
{{ include "orioledb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Generate scripts configmap
*/}}
{{- define "orioledb.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Define orioledb component definition regular expression name prefix
*/}}
{{- define "orioledb.cmpdRegexpPattern" -}}
^orioledb.*
{{- end -}}

{{/*
Define orioledb component config template name
*/}}
{{- define "orioledb.configTemplate" -}}
orioledb-config-{{ .Chart.Version }}
{{- end -}}

{{/*
Define orioledb component config constraint name
*/}}
{{- define "orioledb.configConstraint" -}}
orioledb-cc-{{ .Chart.Version }}
{{- end -}}


{{/*
Define orioledb component definition name
*/}}
{{- define "orioledb.cmpdName" -}}
{{- if .Values.cmpdVersionPrefix.orioledb.major16.minorAll -}}
orioledb-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.orioledb.major16.minorAll -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Generate scripts configmap
*/}}
{{- define "orioledb.extend.reload.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "reloader/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Define postgresql script template name
*/}}
{{- define "orioledb.scriptTemplate" -}}
orioledb-script
{{- end -}}

{{/*
Define postgresql reload script template name
*/}}
{{- define "orioledb.reloader.scripts" -}}
orioledb-reload-tools-script
{{- end -}}


{{- define "orioledb.spec.common" -}}
provider: kubeblocks
description: {{ .Chart.Description }}
serviceKind: orioledb
services:
  - name: default
    spec:
      ports:
          - name: orioledb
            port: 5432
            targetPort: tcp-orioledb
    roleSelector: primary
volumes:
  - highWatermark: 0
    name: data
    needSnapshot: false
roles:
  - name: primary
    updatePriority: 3
    participatesInQuorum: true
  - name: secondary
    updatePriority: 2
    participatesInQuorum: true
vars:
  ## the postgres leader pod name which is dynamically selected, caution to use it
  - name: POSTGRES_LEADER_POD_NAME
    valueFrom:
      componentVarRef:
        compDef: {{ include "orioledb.cmpdName" . }}
        optional: true
        podNamesForRole:
          role: primary
          option: Optional
  - name: POSTGRES_USER
    valueFrom:
      credentialVarRef:
        name: postgres
        optional: false
        username: Required
  - name: POSTGRES_PASSWORD
    valueFrom:
      credentialVarRef:
        name: postgres
        optional: false
        password: Required
  # env for syncer to initialize dcs
  # TODO: modify these env for syncer
  - name: CLUSTER_NAME
    valueFrom:
      clusterVarRef:
        clusterName: Required
  - name: MY_COMP_NAME
    valueFrom:
      componentVarRef:
        optional: false
        shortName: Required
  - name: MY_NAMESPACE
    valueFrom:
      clusterVarRef:
        namespace: Required
  - name: TLS_ENABLED
    valueFrom:
      tlsVarRef:
        enabled: Optional
systemAccounts:
  - name: postgres
    initAccount: true
    passwordGenerationPolicy:
      length: 10
      numDigits: 5
      numSymbols: 0
      letterCase: MixedCases
  - name: kbadmin
    passwordGenerationPolicy:
      length: 10
      letterCase: MixedCases
      numDigits: 5
      numSymbols: 0
    statement:
      create: CREATE USER ${KB_ACCOUNT_NAME} SUPERUSER PASSWORD '${KB_ACCOUNT_PASSWORD}';
tls:
  volumeName: tls
  mountPath: /etc/pki/tls
  caFile: ca.pem
  certFile: cert.pem
  keyFile: key.pem
lifecycleActions:
  roleProbe:
    periodSeconds: 5
    timeoutSeconds: 1
    exec:
      container: orioledb
      command:
        - /tools/syncerctl
        - getrole
  switchover:
    exec:
      container: orioledb
      command:
        - /bin/sh
        - -c
        - |
          /tools/syncerctl switchover --primary "$POSTGRES_LEADER_POD_NAME" ${KB_SWITCHOVER_CANDIDATE_NAME:+--candidate "$KB_SWITCHOVER_CANDIDATE_NAME"}
  accountProvision:
    exec:
      container: orioledb
      command:
        - bash
        - -c
        - |
          eval statement=\"${KB_ACCOUNT_STATEMENT}\"
          psql -h 127.0.0.1 -c "${statement}"
      env:
        - name: PGUSER
          value: $(POSTGRES_USER)
        - name: PGPASSWORD
          value: $(POSTGRES_PASSWORD)
      targetPodSelector: Role
      matchingKey: primary
{{- end -}}

{{- define "orioledb.spec.runtime.common" -}}
runtime:
  initContainers:
    - command:
        - sh
        - -c
        - cp -r /bin/syncer /bin/syncerctl /tools/
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.syncer.repository }}:{{ .Values.image.syncer.tag }}
      imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
      name: init-syncer
      volumeMounts:
        - mountPath: /tools
          name: tools
  containers:
    - command:
        - /kb-scripts/setup.sh
      env:
        - name: ALLOW_NOSSL
          value: 'true'
        - name: POD_IP
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: status.podIP
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
        - name: PGUSER
          value: $(POSTGRES_USER)
        - name: PGPASSWORD
          value: $(POSTGRES_PASSWORD)
        - name: POSTGRESQL_PORT_NUMBER
          value: '5432'
        - name: PGDATA
          value: {{ .Values.dataPath }}
        - name: PGCONF
          value: {{ .Values.confPath }}
        # orioledb is a postgresql compatible database, in syncer, it is treated as vanilla-postgresql
        - name: KB_ENGINE_TYPE
          value: vanilla-postgresql
        - name: KB_CLUSTER_NAME
          value: $(CLUSTER_NAME)
        - name: POSTGRESQL_MOUNTED_CONF_DIR
          value: {{ .Values.confMountPath }}
        - name: POSTGRES_INITDB_ARGS
          value: "--locale=C"
        - name: MY_POD_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.name
        - name: MY_POD_UID
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.uid
        - name: MY_POD_IP
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: status.podIP
        - name: KB_COMP_NAME
          value: $(MY_COMP_NAME)
        - name: KB_POD_NAME
          value: $(MY_POD_NAME)
        - name: KB_POD_UID
          value: $(MY_POD_UID)
        - name: KB_POD_IP
          value: $(MY_POD_IP)
        - name: KB_POD_NAMESPACE
          value: $(MY_NAMESPACE)
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
      imagePullPolicy: IfNotPresent
      name: orioledb
      ports:
        - containerPort: 5432
          name: tcp-orioledb
        - name: ha
          protocol: TCP
          containerPort: 3601
      securityContext:
        runAsUser: 0
      volumeMounts:
        - mountPath: /dev/shm
          name: dshm
        - mountPath: {{ .Values.dataMountPath }}
          name: data
        - mountPath: {{ .Values.confMountPath }}
          name: postgresql-config
        - mountPath: /kb-scripts
          name: scripts
        - mountPath: /tools
          name: tools
  volumes:
    - emptyDir:
        medium: Memory
      name: dshm
{{- end -}}
