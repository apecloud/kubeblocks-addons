{{/*
Expand the name of the chart.
*/}}
{{- define "mysql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mysql.fullname" -}}
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
Create the name of the service account to use
*/}}
{{- define "mysql.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mysql.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Define mysql component defintion name
*/}}
{{- define "mysql.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
mysql
{{- else -}}
{{- printf "mysql-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define mysql component defintion name
*/}}
{{- define "orchestrator.serviceRefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
orchestrator
{{- else -}}
{{- printf "orchestrator-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

{{/*
Define mysql component defintion name
*/}}
{{- define "proxysql.componentDefName" -}}
{{- if eq (len .Values.compDefinitionVersionSuffix) 0 -}}
proxysql
{{- else -}}
{{- printf "proxysql-%s" .Values.compDefinitionVersionSuffix -}}
{{- end -}}
{{- end -}}

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
app.kubernetes.io/name: {{ include "mysql.componentDefName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "mysql.imagePullPolicy" -}}
{{ default "IfNotPresent" .Values.image.pullPolicy }}
{{- end }}

{{- define "mysql.spec.common" -}}
provider: kubeblocks
description: mysql component definition for Kubernetes
serviceKind: mysql
serviceVersion: 8.0.33
updateStrategy: BestEffortParallel

services:
  - name: mysql-server
    serviceName: mysql-server
    spec:
      ports:
        - name: mysql
          port: 3306
          targetPort: mysql
  - name: mysql
    serviceName: mysql
    podService: true
    spec:
      ports:
        - name: mysql
          port: 3306
          targetPort: mysql

scripts:
  - name: mysql-scripts
    templateRef: mysql-scripts
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
vars:
  - name: MYSQL_ROOT_USER
    valueFrom:
      credentialVarRef:
        ## reference the current component definition name
        compDef: {{ include "mysql.componentDefName" . }}
        name: root
        username: Required


  - name: MYSQL_ROOT_PASSWORD
    valueFrom:
      credentialVarRef:
        ## reference the current component definition name
        compDef: {{ include "mysql.componentDefName" . }}
        name: root
        password: Required
{{- end }}

{{- define "mysql.spec.runtime.common" -}}
- command:
    - cp
    - -r
    - /bin/syncer
    - /config
    - /kubeblocks/
  image: infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/syncer:latest
  imagePullPolicy: {{ include "mysql.imagePullPolicy" . }}
  name: init-syncer
  volumeMounts:
    - mountPath: /kubeblocks
      name: kubeblocks
- command:
    - cp
    - -r
    - /xtrabackup-2.4
    - /kubeblocks/xtrabackup
  image: infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/syncer:mysql
  imagePullPolicy: {{ default .Values.image.pullPolicy "IfNotPresent" }}
  name: init-xtrabackup
  volumeMounts:
    - mountPath: /kubeblocks
      name: kubeblocks
{{- end }}

{{- define "mysql-orc.spec.common"}}
labels:
  kubeblocks.io/ready-without-primary: "true"
provider: kubeblocks
description: mysql 5.7 component definition for Kubernetes
serviceKind: mysql
serviceVersion: 5.7.44
updateStrategy: BestEffortParallel

serviceRefDeclarations:
  - name: orchestrator
    serviceRefDeclarationSpecs:
      - serviceKind: orchestrator
        serviceVersion: "^*"
services:
  - name: mysql-server
    serviceName: mysql-server
    spec:
      ports:
        - name: mysql
          port: 3306
          targetPort: mysql
  - name: mysql
    serviceName: mysql
    podService: true
    spec:
      ports:
        - name: mysql
          port: 3306
          targetPort: mysql
configs:
  - name: mysql-replication-config
    templateRef: mysql-5.7-config-template
    constraintRef: mysql-config-constraints
    volumeName: mysql-config
    namespace: {{ .Release.Namespace }}
scripts:
  - name: mysql-scripts
    templateRef: mysql-scripts
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

roles:
  - name: primary
    serviceable: true
    writable: true
  - name: secondary
    serviceable: true
    writable: false
lifecycleActions:
  roleProbe:
    builtinHandler: custom
    customHandler:
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
      exec:
        command:
          - /bin/bash
          - -c
          - |
            topology_info=$(/kubeblocks/orchestrator-client -c topology -i $KB_CLUSTER_NAME) || true
            if [[ $topology_info == "" ]]; then
              echo -n "secondary"
              exit 0
            fi

            first_line=$(echo "$topology_info" | head -n 1)
            cleaned_line=$(echo "$first_line" | tr -d '[]')
            old_ifs="$IFS"
            IFS=',' read -ra status_array <<< "$cleaned_line"
            IFS="$old_ifs"
            status="${status_array[1]}"
            if  [ "$status" != "ok" ]; then
              exit 0
            fi

            address_port=$(echo "$first_line" | awk '{print $1}')
            master_from_orc="${address_port%:*}"
            last_digit=${KB_POD_NAME##*-}
            self_service_name=$(echo "${KB_CLUSTER_COMP_NAME}_mysql_${last_digit}" | tr '_' '-' | tr '[:upper:]' '[:lower:]' )
            if [ "$master_from_orc" == "${self_service_name}" ]; then
              echo -n "primary"
            else
              echo -n "secondary"
            fi
  postProvision:
    customHandler:
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
      exec:
        command:
          - bash
          - -c
          - "/scripts/mysql-orchestrator-register.sh;"
      preCondition: ComponentReady
  preTerminate:
    customHandler:
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
      exec:
        command:
          - bash
          - -c
          - "curl http://${ORC_ENDPOINTS%%:*}:${ORC_PORTS}/api/forget-cluster/${KB_CLUSTER_NAME};"
  memberLeave:
    customHandler:
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
      exec:
        command:
          - /bin/sh
          - -c
          - |
            last_digit=${KB_LEAVE_MEMBER_POD_NAME##*-}
            self_service_name=$(echo "${KB_CLUSTER_COMP_NAME}_mysql_${last_digit}" | tr '_' '-' | tr '[:upper:]' '[:lower:]' )
            /kubeblocks/orchestrator-client -c forget -i ${self_service_name}:3306
      targetPodSelector: Any
      container: mysql

vars:
  - name: MYSQL_ROOT_USER
    valueFrom:
      credentialVarRef:
        ## reference the current component definition name
        compDef: {{ include "mysql.componentDefName" . }}
        name: root
        username: Required


  - name: MYSQL_ROOT_PASSWORD
    valueFrom:
      credentialVarRef:
        ## reference the current component definition name
        compDef: {{ include "mysql.componentDefName" . }}
        name: root
        password: Required


  - name: MYSQL_PORT
    valueFrom:
      serviceVarRef:
        compDef: {{ include "mysql.componentDefName" . }}
        name: mysql
        optional: true
        port:
          name: mysql
          option: Optional

  - name: MYSQL_ORDINAL_HOST
    valueFrom:
      serviceVarRef:
        compDef: {{ include "mysql.componentDefName" . }}
        name: mysql
        host: Required

  - name: ORC_ENDPOINTS
    valueFrom:
      serviceRefVarRef:
        compDef: {{ include "mysql.componentDefName" . }}
        name: orchestrator
        endpoint: Required

  - name: ORC_PORTS
    valueFrom:
      serviceRefVarRef:
        compDef: {{ include "mysql.componentDefName" . }}
        name: orchestrator
        port: Required
{{- end }}

{{- define "mysql-orc.spec.initcontainer.common"}}
- command:
    - /bin/sh
    - -c
    - |
      cp -r /usr/bin/jq /kubeblocks/jq
      cp -r /scripts/orchestrator-client /kubeblocks/orchestrator-client
      cp -r /usr/local/bin/curl /kubeblocks/curl
  image: {{ .Values.image.registry | default "docker.io" }}/apecloud/orc-tools:1.0.0
  imagePullPolicy: {{ default .Values.image.pullPolicy "IfNotPresent" }}
  name: init-jq
  volumeMounts:
    - mountPath: /kubeblocks
      name: kubeblocks
- command:
    - cp
    - -r
    - /xtrabackup-2.4
    - /kubeblocks/xtrabackup
  image: infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/syncer:mysql
  imagePullPolicy: {{ default .Values.image.pullPolicy "IfNotPresent" }}
  name: init-xtrabackup
  volumeMounts:
    - mountPath: /kubeblocks
      name: kubeblocks
{{- end }}