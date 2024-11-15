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
Define apecloud postgresql 14 component definition name prefix
*/}}
{{- define "apecloud-postgresql14.componentDefNamePrefix" -}}
{{- if eq (len .Values.cmpdVersionPrefix.apecloudPostgresql14) 0 -}}
{{- printf "apecloud-postgresql14-" -}}
{{- else -}}
{{- printf "%s-" .Values.cmpdVersionPrefix.apecloudPostgresql14 -}}
{{- end -}}
{{- end -}}

{{/*
Define apecloud postgresql 14 component configuration template name
*/}}
{{- define "apecloud-postgresql14.configurationTemplate" -}}
apecloud-postgresql14-configuration-{{ .Chart.Version }}
{{- end -}}

{{/*
Define apecloud postgresql 14 component config constraint name
*/}}
{{- define "apecloud-postgresql14.configConstraint" -}}
apecloud-postgresql14-cc-{{ .Chart.Version }}
{{- end -}}

{{/*
Define apecloud-postgresql component definition name prefix
*/}}
{{- define "apecloud-postgresql.componentDefNamePrefix" -}}
{{- printf "apecloud-postgresql-" -}}
{{- end -}}

{{/*
Define apecloud-postgresql14 component definition name
*/}}
{{- define "apecloud-postgresql.compDefApecloudPostgresql14" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
apecloud-postgresql14-{{ .Chart.Version }}
{{- else -}}
{{- .Values.resourceNamePrefix -}}-{{ .Chart.Version }}
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
            targetPort: postgresql
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
vars:
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
  # syncer env
  - name: KB_CLUSTER_NAME
    valueFrom:
      clusterVarRef:
        clusterName: Required
  - name: KB_COMP_NAME
    valueFrom:
      componentVarRef:
        optional: false
        shortName: Required
  - name: KB_NAMESPACE
    valueFrom:
      clusterVarRef:
        namespace: Required

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
    statement: CREATE USER ${KB_ACCOUNT_NAME} SUPERUSER PASSWORD '${KB_ACCOUNT_PASSWORD}';
lifecycleActions:
  roleProbe:
    periodSeconds: 1
    timeoutSeconds: 1
    exec:
      container: postgresql
      command:
        - /tools/dbctl
        - --config-path
        - /tools/config/dbctl/components
        - apecloud-postgresql
        - getrole
  memberLeave:
    exec:
      container: postgresql
      command:
        - /tools/dbctl
        - --config-path
        - /tools/config/dbctl/components
        - apecloud-postgresql
        - leavemember
  accountProvision:
    exec:
      container: postgresql
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

{{- define "apecloud-postgresql.spec.runtime.common" -}}
runtime:
  initContainers:
    - command:
        - sh
        - -c
        - cp -r /bin/syncer /tools/
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