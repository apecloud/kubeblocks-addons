{{/*
Expand the name of the chart.
*/}}
{{- define "greatsql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "greatsql.fullname" -}}
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
{{- define "greatsql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "greatsql.labels" -}}
helm.sh/chart: {{ include "greatsql.chart" . }}
{{ include "greatsql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "greatsql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "greatsql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "greatsql.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "greatsql.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}



{{/*
Define greatsql component definition regex regular
*/}}
{{- define "greatsql.componentDefRegex" -}}
^greatsql-\d+\.\d+.*$
{{- end -}}

{{- define "greatsql.componentDefMGRRegex" -}}
^greatsql-mgr-\d+\.\d+.*$
{{- end -}}

{{- define "greatsql.componentDefOrcRegex" -}}
^greatsql-orc-\d+\.\d+.*$
{{- end -}}

{{/*
Define greatsql component definition name
*/}}
{{- define "greatsql.componentDefName80" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
greatsql-8.0
{{- else -}}
{{- printf "greatsql-8.0-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{- define "greatsql.imagePullPolicy" -}}
{{ default "IfNotPresent" .Values.image.pullPolicy }}
{{- end }}

{{/*
Defined the specification for the common parts of greatsql in syncer mode
*/}}
{{- define "greatsql.spec.common" -}}
provider: kubeblocks
serviceKind: greatsql
description: greatsql component definition for Kubernetes
updateStrategy: BestEffortParallel

services:
  - name: default
    roleSelector: primary
    spec:
      ports:
        - name: greatsql
          port: 3306
          targetPort: greatsql
logConfigs:
  {{- range $name,$pattern := .Values.logConfigs }}
  - name: {{ $name }}
    filePathPattern: {{ $pattern }}
  {{- end }}
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
lifecycleActions:
  roleProbe:
    builtinHandler: mysql
    periodSeconds: {{ .Values.roleProbe.periodSeconds }}
    timeoutSeconds: {{ .Values.roleProbe.timeoutSeconds }}
  accountProvision:
    customHandler:
      container: greatsql
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
roles:
  - name: primary
    serviceable: true
    writable: true
  - name: secondary
    serviceable: true
    writable: false
systemAccounts:
  - name: root
    initAccount: true
    passwordGenerationPolicy:
      length: 16
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
  - name: kbadmin
    statement: select 1;
    passwordGenerationPolicy: &defaultPasswordGenerationPolicy
      length: 16
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
  - name: kbdataprotection
    statement: CREATE USER $(USERNAME) IDENTIFIED BY '$(PASSWD)';GRANT RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT ON *.* TO $(USERNAME); GRANT LOCK TABLES,RELOAD,PROCESS,REPLICATION CLIENT, SUPER,SELECT,EVENT,TRIGGER,SHOW VIEW ON *.* TO $(USERNAME);
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbprobe
    statement: CREATE USER $(USERNAME) IDENTIFIED BY '$(PASSWD)'; GRANT REPLICATION CLIENT, PROCESS ON *.* TO $(USERNAME); GRANT SELECT ON performance_schema.* TO $(USERNAME);
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbmonitoring
    statement: CREATE USER $(USERNAME) IDENTIFIED BY '$(PASSWD)'; GRANT REPLICATION CLIENT, PROCESS ON *.* TO $(USERNAME); GRANT SELECT ON performance_schema.* TO $(USERNAME);
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
  - name: kbreplicator
    statement: select 1;
    passwordGenerationPolicy: *defaultPasswordGenerationPolicy
{{- end }}

{{- define "greatsql.spec.runtime.common" -}}
- command:
    - cp
    - -r
    - /bin/syncer
    - /bin/syncerctl
    - /tools/
  image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.syncer.repository }}:{{ .Values.image.syncer.tag }}
  imagePullPolicy: {{ default "IfNotPresent" .Values.image.pullPolicy }}
  name: init-syncer
  volumeMounts:
    - mountPath: /tools
      name: tools
{{- end }}