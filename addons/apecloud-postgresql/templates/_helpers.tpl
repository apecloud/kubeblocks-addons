{{/*
Common annotations
*/}}
{{- define "apecloud-postgresql.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "apecloud-postgresql.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "apecloud-postgresql.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Expand the name of the chart.
*/}}
{{- define "apecloud-postgresql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "apecloud-postgresql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "apecloud-postgresql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "apecloud-postgresql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "apecloud-postgresql.labels" -}}
helm.sh/chart: {{ include "apecloud-postgresql.chart" . }}
{{ include "apecloud-postgresql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Generate scripts configmap
*/}}
{{- define "apecloud-postgresql.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}


{{/*
Define apecloud postgresql 14.X component definition regular expression name prefix
*/}}
{{- define "apecloud-postgresql-14.cmpdRegexpPattern" -}}
^apecloud-postgresql-14.*
{{- end -}}

{{/*
Define apecloud postgresql 14 component configuration template name
*/}}
{{- define "apecloud-postgresql-14.configurationTemplate" -}}
apecloud-postgresql-14-configuration-{{ .Chart.Version }}
{{- end -}}

{{/*
Define apecloud postgresql 14 component config constraint name
*/}}
{{- define "apecloud-postgresql-14.pdName" -}}
apecloud-postgresql-14-pd
{{- end -}}

{{/*
Define apecloud postgresql 14 component config constraint name
*/}}
{{- define "apecloud-postgresql-14.pcrName" -}}
apecloud-postgresql-14-pcr
{{- end -}}

{{/*
Define apecloud-postgresql component definition regular expression name prefix
*/}}
{{- define "apecloud-postgresql.cmpdRegexpPattern" -}}
^apecloud-postgresql-\d+
{{- end -}}

{{/*
Define apecloud-postgresql 14.X component definition name
*/}}
{{- define "apecloud-postgresql-14.cmpdName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.apecloudPostgresql.major14.minorAll ) 0 -}}
apecloud-postgresql-14-{{ .Chart.Version }}
{{- else -}}
{{- printf "%s" .Values.cmpdVersionPrefix.apecloudPostgresql.major14.minorAll -}}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Generate scripts configmap
*/}}
{{- define "apecloud-postgresql.extend.reload.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "reloader/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Define postgresql scripts configMap template name
*/}}
{{- define "apecloud-postgresql.scriptsTemplate" -}}
apecloud-postgresql-scripts
{{- end -}}

{{/*
Define postgresql scripts configMap template name
*/}}
{{- define "apecloud-postgresql.reloader.scripts" -}}
apecloud-postgresql-reload-tools-script
{{- end -}}


{{- define "apecloud-postgresql.spec.common" -}}
provider: kubeblocks
description: {{ .Chart.Description }}
serviceKind: postgresql
services:
  - name: default
    spec:
      ports:
          - name: postgresql
            port: 5432
            targetPort: tcp-postgresql
    roleSelector: leader
  - name: replication
    serviceName: replication
    spec:
      ports:
        - name: raft
          port: 15432
          targetPort: raft
    podService: true
    disableAutoProvision: true
volumes:
  - highWatermark: 0
    name: data
    needSnapshot: false
roles:
  - name: leader
    updatePriority: 3
    participatesInQuorum: true
  - name: follower
    updatePriority: 2
    participatesInQuorum: true
  - name: learner
    updatePriority: 1
    participatesInQuorum: false
vars:
  ## the postgres leader pod name which is dynamically selected, caution to use it
  - name: POSTGRES_LEADER_POD_NAME
    valueFrom:
      componentVarRef:
        compDef: {{ include "apecloud-postgresql-14.cmpdName" . }}
        optional: true
        podNamesForRole:
          role: leader
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
  - name: CLUSTER_NAME
    valueFrom:
      clusterVarRef:
        clusterName: Required
  - name: COMPONENT_NAME
    valueFrom:
      componentVarRef:
        optional: false
        shortName: Required
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
    periodSeconds: 1
    timeoutSeconds: 1
    exec:
      container: postgresql
      command:
        - /tools/syncerctl
        - getrole
  switchover:
    exec:
      command:
        - /bin/sh
        - -c
        - |

          if [ "$KB_SWITCHOVER_ROLE" != "leader" ]; then
              echo "switchover not triggered for leader, nothing to do, exit 0."
              exit 0
          fi
          
          /tools/syncerctl switchover --primary "$POSTGRES_LEADER_POD_NAME" ${KB_SWITCHOVER_CANDIDATE_NAME:+--candidate "$KB_SWITCHOVER_CANDIDATE_NAME"}
  memberLeave:
    exec:
      container: postgresql
      command:
        - /bin/sh
        - -c
        - |
          /tools/syncerctl leave --instance "$KB_LEAVE_MEMBER_POD_NAME"
  accountProvision:
    exec:
      container: postgresql
      command:
        - /bin/sh
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
      matchingKey: leader
{{- end -}}

{{- define "apecloud-postgresql.spec.runtime.common" -}}
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
        - /tools/syncer
        - --port
        - '3601'
        - --
        - docker-entrypoint.sh
        - postgres
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
        - name: KB_SERVICE_CHARACTER_TYPE
          value: apecloud-postgresql
        - name: POSTGRESQL_MOUNTED_CONF_DIR
          value: {{ .Values.confMountPath }}
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
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
      imagePullPolicy: IfNotPresent
      name: postgresql
      ports:
        - containerPort: 5432
          name: tcp-postgresql
        - containerPort: 15432
          name: raft
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
