{{/*
Define postgresql cluster definition name
*/}}
{{- define "vanilla-postgresql.clusterDefinition" -}}
vanilla-postgresql
{{- end -}}

{{/*
Define postgresql component version name
*/}}
{{- define "vanilla-postgresql.componentVersion" -}}
vanilla-postgresql
{{- end -}}

{{/*
Define postgresql component definition name prefix
*/}}
{{- define "vanilla-postgresql.componentDefNamePrefix" -}}
{{- printf "vanilla-postgresql-" -}}
{{- end -}}

{{/*
Define vanilla-postgresql 12 component definition name prefix
*/}}
{{- define "vanilla-postgresql12.componentDefNamePrefix" -}}
{{- if eq (len .Values.cmpdVersionPrefix.vanillaPostgresql12) 0 -}}
{{- printf "vanilla-postgresql-12-" -}}
{{- else -}}
{{- printf "%s-" .Values.cmpdVersionPrefix.vanillaPostgresql12 -}}
{{- end -}}
{{- end -}}

{{/*
Define vanilla-postgresql 14 component definition name prefix
*/}}
{{- define "vanilla-postgresql14.componentDefNamePrefix" -}}
{{- if eq (len .Values.cmpdVersionPrefix.vanillaPostgresql14) 0 -}}
{{- printf "vanilla-postgresql-14-" -}}
{{- else -}}
{{- printf "%s-" .Values.cmpdVersionPrefix.vanillaPostgresql14 -}}
{{- end -}}
{{- end -}}

{{/*
Define vanilla-postgresql 12 component definition name
*/}}
{{- define "vanilla-postgresql12.compDefName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.vanillaPostgresql12) 0 -}}
vanilla-postgresql-12
{{- else -}}
{{ .Values.cmpdVersionPrefix.vanillaPostgresql12 }}
{{- end -}}
{{- end -}}

{{/*
Define vanilla-postgresql 14 component definition name with Chart.Version suffix
*/}}
{{- define "vanilla-postgresql14.compDefName" -}}
{{- if eq (len .Values.cmpdVersionPrefix.vanillaPostgresql14) 0 -}}
vanilla-postgresql-14
{{- else -}}
{{ .Values.cmpdVersionPrefix.vanillaPostgresql14 }}
{{- end -}}
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
Define vanillaPostgresql12 component configuration template name
*/}}
{{- define "vanilla-postgresql12.configurationTemplate" -}}
vanilla-postgresql12-configuration
{{- end -}}

{{/*
Define postgresql14 component configuration template name
*/}}
{{- define "vanilla-postgresql14.configurationTemplate" -}}
vanilla-postgresql14-configuration
{{- end -}}

{{/*
Define postgresql12 component config constraint name
*/}}
{{- define "vanilla-postgresql12.configConstraint" -}}
vanilla-postgresql12-cc
{{- end -}}

{{/*
Define postgresql14 component config constraint name
*/}}
{{- define "vanilla-postgresql14.configConstraint" -}}
vanilla-postgresql14-cc
{{- end -}}

{{/*
Define postgresql scripts configMap template name
*/}}
{{- define "vanilla-postgresql.scriptsTemplate" -}}
vanilla-postgresql-scripts
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

{{- define "vanilla-postgresql.spec.common" -}}
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
        name: postgres
        optional: false
        username: Required
  - name: POSTGRES_PASSWORD
    valueFrom:
      credentialVarRef:
        name: postgres
        optional: false
        password: Required
lifecycleActions:
  roleProbe:
    builtinHandler: postgresql
    periodSeconds: 1
    timeoutSeconds: 1
systemAccounts:
  - name: postgres
    initAccount: true
    passwordGenerationPolicy:
      length: 10
      numDigits: 5
      numSymbols: 0
      letterCase: MixedCases
{{- end -}}

{{- define "vanilla-postgresql.spec.runtime.common" -}}
initContainers:
  - name: init-syncer
    image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.syncer.repository }}:{{ .Values.image.syncer.tag }}
    imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
    command:
      - sh
      - -c
      - "cp -r /bin/syncer /kubeblocks/"
    volumeMounts:
      - name: kubeblocks
        mountPath: /kubeblocks
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
name: postgresql
imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
securityContext:
  runAsUser: 0
command:
  - /kubeblocks/syncer
  - --config-path
  - /kubeblocks/config/components
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
  - name: kubeblocks
    mountPath: /kubeblocks
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
  # used by syncer
  - name: KB_ENGINE_TYPE
    value: vanilla-postgresql
{{- end -}}