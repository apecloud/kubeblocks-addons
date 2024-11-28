{{/*
Common annotations
*/}}
{{- define "vanilla-postgresql.annotations" -}}
helm.sh/resource-policy: keep
{{- end }}

{{/*
Define vanilla-postgresql component definition regular expression name prefix
*/}}
{{- define "vanilla-postgresql.cmpdRegexpPattern" -}}
^(vanilla-postgresql-\w+)
{{- end -}}

{{/*
Define vanilla-postgresql 12.X component definition regular expression name prefix
*/}}
{{- define "vanilla-postgresql-12.cmpdRegexpPattern" -}}
^vanilla-postgresql-12.*
{{- end -}}

{{/*
Define vanilla-postgresql 14.X component definition regular expression name prefix
*/}}
{{- define "vanilla-postgresql-14.cmpdRegexpPattern" -}}
^vanilla-postgresql-14.*
{{- end -}}

{{/*
Define vanilla-postgresql 15.X component definition regular expression name prefix
*/}}
{{- define "vanilla-postgresql-15.cmpdRegexpPattern" -}}
^vanilla-postgresql-15.*
{{- end -}}

{{/*
Define vanilla-postgresql-supabase15.X component definition regular expression name prefix
*/}}
{{- define "vanilla-postgresql-supabase15.cmpdRegexpPattern" -}}
^vanilla-postgresql-supabase15.*
{{- end -}}

{{/*
Define vanilla-postgresql 12 component definition name with Chart.Version suffix
*/}}
{{- define "vanilla-postgresql12.compDefName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.major12) 0 -}}
vanilla-postgresql-12-{{ .Chart.Version }}
{{- else -}}
{{ .Values.cmpdVersionPrefix.major12 }}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define vanilla-postgresql 14 component definition name with Chart.Version suffix
*/}}
{{- define "vanilla-postgresql14.compDefName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.major14) 0 -}}
vanilla-postgresql-14-{{ .Chart.Version }}
{{- else -}}
{{ .Values.cmpdVersionPrefix.major14 }}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define vanilla-postgresql 15 component definition name with Chart.Version suffix
*/}}
{{- define "vanilla-postgresql15.compDefName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.major15) 0 -}}
vanilla-postgresql-15-{{ .Chart.Version }}
{{- else -}}
{{ .Values.cmpdVersionPrefix.major15 }}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define vanilla-postgresql-supabase 15 component definition name with Chart.Version suffix
*/}}
{{- define "vanilla-postgresql-supabase15.compDefName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.supabaseMajor15) 0 -}}
vanilla-postgresql-supabase15-{{ .Chart.Version }}
{{- else -}}
{{ .Values.cmpdVersionPrefix.supabaseMajor15 }}-{{ .Chart.Version }}
{{- end -}}
{{- end -}}

{{/*
Define vanillap ostgresql scripts configMap template name
*/}}
{{- define "vanilla-postgresql.reloader.scripts" -}}
vanilla-postgresql-reload-tools-script
{{- end -}}

{{/*
Expand the name of the chart.
*/}}
{{- define "vanilla-postgresql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "vanilla-postgresql.fullname" -}}
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
{{- define "vanilla-postgresql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vanilla-postgresql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vanilla-postgresql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vanilla-postgresql.labels" -}}
helm.sh/chart: {{ include "vanilla-postgresql.chart" . }}
{{ include "vanilla-postgresql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Define vanilla-postgresql 12 component configuration template name
*/}}
{{- define "vanilla-postgresql12.configurationTemplate" -}}
vanilla-postgresql12-configuration
{{- end -}}

{{/*
Define vanilla-postgresql 14 component configuration template name
*/}}
{{- define "vanilla-postgresql14.configurationTemplate" -}}
vanilla-postgresql14-configuration
{{- end -}}

{{/*
Define vanilla-postgresql 15 component configuration template name
*/}}
{{- define "vanilla-postgresql15.configurationTemplate" -}}
vanilla-postgresql15-configuration
{{- end -}}

{{/*
Define vanilla-postgresql-supabase 15 component configuration template name
*/}}
{{- define "vanilla-postgresql-supabase15.configurationTemplate" -}}
vanilla-postgresql-supabase15-configuration
{{- end -}}

{{/*
Define vanilla-postgresql 12 component config constraint name
*/}}
{{- define "vanilla-postgresql12.configConstraint" -}}
vanilla-postgresql12-cc
{{- end -}}

{{/*
Define vanilla-postgresql 14 component config constraint name
*/}}
{{- define "vanilla-postgresql14.configConstraint" -}}
vanilla-postgresql14-cc
{{- end -}}

{{/*
Define vanilla-postgresql 15 component config constraint name
*/}}
{{- define "vanilla-postgresql15.configConstraint" -}}
vanilla-postgresql15-cc
{{- end -}}

{{/*
Define vanilla-postgresql scripts configMap template name
*/}}
{{- define "vanilla-postgresql.scriptsTemplate" -}}
vanilla-postgresql-scripts-{{ .Chart.Version }}
{{- end -}}

{{/*
Generate scripts configmap
*/}}
{{- define "vanilla-postgresql.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate scripts configmap
*/}}
{{- define "vanilla-postgresql.extend.reload.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "reloader/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Define vanilla-postgresql base backup actionset name
*/}}
{{- define "vanilla-postgresql.actionset.basebackup" -}}
vanilla-pg-basebackup
{{- end -}}

{{- define "vanilla-postgresql.spec.common" -}}
{{- $rootAccount := default "postgres" .accountName -}}
provider: kubeblocks
description: {{ .Chart.Description }}
serviceKind: postgresql
logConfigs:
  {{- range $name,$pattern := .Values.logConfigs }}
  - name: {{ $name }}
    filePathPattern: {{ $pattern }}
  {{- end }}
services:
  - name: vanilla-postgresql
    spec:
      ports:
        - name: tcp-postgresql
          port: 5432
          targetPort: tcp-postgresql
    roleSelector: primary
roles:
  - name: primary
    serviceable: true
    writable: true
  - name: secondary
    serviceable: true
    writable: false
volumes:
  - name: data
    needSnapshot: true
updateStrategy: BestEffortParallel
vars:
  - name: POSTGRES_USER
    valueFrom:
      credentialVarRef:
        name: {{ $rootAccount }}
        optional: false
        username: Required
  - name: POSTGRES_PASSWORD
    valueFrom:
      credentialVarRef:
        name: {{ $rootAccount }}
        optional: false
        password: Required
  - name: POSTGRES_PRIMARY_POD_NAME
    valueFrom:
      componentVarRef:
        optional: true
        podNamesForRole:
          role: primary
          option: Optional
  - name: TLS_ENABLED
    valueFrom:
      tlsVarRef:
        enabled: Required
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
        - postgresql
        - getrole
  switchover:
    exec:
      container: postgresql
      command:
        - sh
        - -c
        - /kb-scripts/switchover.sh
systemAccounts:
  - name: {{ $rootAccount }}
    initAccount: true
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
{{- end -}}

{{- define "vanilla-postgresql.spec.runtime.common" -}}
initContainers:
  - name: init-syncer
    image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.syncer.repository }}:{{ .Values.image.syncer.tag }}
    imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
    command:
      - sh
      - -c
      - "cp -r /bin/syncer /tools/"
    volumeMounts:
      - name: tools
        mountPath: /tools
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
securityContext:
  runAsUser: 0
  fsGroup: 103
  runAsGroup: 103
volumes:
  - name: dshm
    emptyDir:
      medium: Memory
          {{- with .Values.shmVolume.sizeLimit }}
      sizeLimit: {{ . }}
          {{- end }}
{{- end -}}

{{- define "vanilla-postgresql.spec.runtime.container.common" -}}
{{- $pg_major := .pg_major -}}
- name: postgresql
  imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
  securityContext:
    runAsUser: 0
  command:
    - /tools/syncer
    - --port
    - "3601"
    - --
    - docker-entrypoint.sh
    - --config-file={{ .Values.confPath }}/postgresql.conf
    - --hba_file={{ .Values.confPath }}/pg_hba.conf
  volumeMounts:
    - name: dshm
      mountPath: /dev/shm
    - name: data
      mountPath: {{ .Values.dataMountPath }}
    - name: postgresql-config
      mountPath: {{ .Values.confMountPath }}
    - name: scripts
      mountPath: /kb-scripts
    - mountPath: /tools
      name: tools
  ports:
    - name: tcp-postgresql
      containerPort: 5432
  env:
    - name: ALLOW_NOSSL
      value: "true"
    - name: POSTGRESQL_PORT_NUMBER
      value: "5432"
    - name: PGDATA
      value: {{ .Values.dataPath }}
    - name: PGCONF
      value: {{ .Values.confPath }}
    - name: POSTGRESQL_MOUNTED_CONF_DIR
      value: {{ .Values.confMountPath }}
    - name: PGUSER
      value: $(POSTGRES_USER)
    - name: PGPASSWORD
      value: $(POSTGRES_PASSWORD)
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
    # used by syncer
    - name: KB_ENGINE_TYPE
      value: vanilla-postgresql
    {{- if $pg_major }}
    - name: PG_MAJOR
      value: "{{ $pg_major }}"
    {{- end }}
{{- end -}}
