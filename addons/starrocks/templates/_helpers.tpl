{{/*
Expand the name of the chart.
*/}}
{{- define "starrocks.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "starrocks.fullname" -}}
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
{{- define "starrocks.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "starrocks.labels" -}}
helm.sh/chart: {{ include "starrocks.chart" . }}
{{ include "starrocks.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "starrocks.selectorLabels" -}}
app.kubernetes.io/name: {{ include "starrocks.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "starrocks.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "starrocks.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "starrocks.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define component defintion name
*/}}
{{- define "fe-shared-data.componentDefName" -}}
starrocks-fe-sd-{{ .Chart.Version }}
{{- end -}}

{{/*
Define component defintion name
*/}}
{{- define "fe-shared-nothing.componentDefName" -}}
starrocks-fe-sn-{{ .Chart.Version }}
{{- end -}}

{{/*
Define component defintion name
*/}}
{{- define "cn.componentDefName" -}}
starrocks-cn-{{ .Chart.Version }}
{{- end -}}

{{/*
Define component defintion name
*/}}
{{- define "be.componentDefName" -}}
starrocks-be-{{ .Chart.Version }}
{{- end -}}

{{- define "POD_IP" -}}
POD_IP_V4=
POD_IP_V6=
ips=$(echo $KB_POD_IPS | tr "," "\n")
for ip in $ips; do
    if [[ $ip == *":"* ]]; then
        POD_IP_V6=$ip
    else
        POD_IP_V4=$ip
    fi
done
if [[ "$IP_FAMILY" == "IPv4" ]]; then
    POD_IP=$POD_IP_V4
else
    POD_IP=$POD_IP_V6
fi
if [[ -z "$POD_IP" ]]; then
    echo "Failed to get $IP_FAMILY POD_IP from KB_POD_IPS"
    exit 1
fi
{{- end -}}

{{- define "fe.probe" -}}
{{- if eq .Values.hostType "FQDN" -}}
httpGet:
  path: /api/health
  port: 8030
  scheme: HTTP
{{- else -}}
exec:
  command:
  - /bin/bash
  - -c
  - |
{{ include "POD_IP" . | indent 4 }}
    {{- if eq .Values.ipFamily "IPv6" }}
    POD_IP="[$POD_IP]"
    {{- end }}
    curl --fail http://$POD_IP:8030/api/health
{{- end }}
periodSeconds: 5
successThreshold: 1
timeoutSeconds: 1
{{- end -}}

{{- define "be.probe" -}}
{{- if eq .Values.hostType "FQDN" -}}
httpGet:
  path: /api/health
  port: 8040
  scheme: HTTP
{{- else -}}
exec:
  command:
  - /bin/bash
  - -c
  - |
{{ include "POD_IP" . | indent 4 }}
    {{- if eq .Values.ipFamily "IPv6" }}
    POD_IP="[$POD_IP]"
    {{- end }}
    curl --fail http://$POD_IP:8040/api/health
{{- end }}
periodSeconds: 5
successThreshold: 1
timeoutSeconds: 1
{{- end -}}

{{- define "cn.probe" -}}
{{- if eq .Values.hostType "FQDN" -}}
httpGet:
  path: /api/health
  port: 8040
  scheme: HTTP
{{- else -}}
exec:
  command:
  - /bin/bash
  - -c
  - |
{{ include "POD_IP" . | indent 4 }}
    {{- if eq .Values.ipFamily "IPv6" }}
    POD_IP="[$POD_IP]"
    {{- end }}
    curl --fail http://$POD_IP:8040/api/health
{{- end }}
periodSeconds: 5
successThreshold: 1
timeoutSeconds: 1
{{- end -}}

{{- define "fe.serviceRefDeclarations" }}
serviceRefDeclarations:
- name: s3-object-storage
  optional: false
  serviceRefDeclarationSpecs:
  - serviceKind: minio
    serviceVersion: "^*"
{{- end }}

{{- define "fe.serviceRefVars" }}
- name: S3_ENDPOINT
  valueFrom:
    serviceRefVarRef:
      name: s3-object-storage
      optional: false
      endpoint: Required
- name: S3_ACCESS_KEY
  valueFrom:
    serviceRefVarRef:
      name: s3-object-storage
      optional: false
      username: Required
- name: S3_SECRET_KEY
  valueFrom:
    serviceRefVarRef:
      name: s3-object-storage
      optional: false
      password: Required
{{- end }}

{{- define "fe.commonDef" -}}
serviceKind: starrocks-fe
services:
  - name: fe
    serviceName: fe
    spec:
      ipFamilies:
      - IPv4
      ipFamilyPolicy: PreferDualStack
      ports:
      - name: fe-http
        port: 8030
        targetPort: http-port
      - name: fe-mysql
        port: {{ .Values.fe.queryPort }}
        targetPort: query-port
# The FE can only perform leader election when the majority of members are active.
updateStrategy: Parallel
volumes:
  - name: data
    needSnapshot: true
logConfigs:
  {{- range $name,$pattern := .Values.fe.logConfigs }}
  - name: {{ $name }}
    filePathPattern: {{ $pattern }}
  {{- end }}
systemAccounts:
- name: root
  initAccount: true
  passwordGenerationPolicy:
    length: 10
    numDigits: 5
    numSymbols: 0
    letterCase: MixedCases
lifecycleActions:
  postProvision:
    customHandler:
      preCondition: ComponentReady
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.fe.repository }}:{{ default .Values.image.fe.tag }}
      exec:
        command:
        - /bin/bash
        - -c
        - |
          function exec_sql() {
            mysql -P{{ .Values.fe.queryPort }} -h${FE_DISCOVERY_ADDR} -u${STARROCKS_USER} -p${STARROCKS_PASSWORD} -e "$1"
          }
          if [ ! -z "${S3_ENDPOINT}" ] && [ ! -z "${S3_BUCKET}" ]; then
            # Ensure S3_ENDPOINT has http/https prefix
            if [[ ! "${S3_ENDPOINT}" =~ ^https?:// ]]; then
                S3_ENDPOINT="http://${S3_ENDPOINT}"
            fi

            if [[ "${S3_PATH}" == "/*" ]]; then
                echo "S3_PATH is invalid, should not start with '/'"
                exit 1
            fi
            if [[ "${S3_PATH}" == "*/" ]]; then
                echo "S3_PATH is invalid, should not end with '/'"
                exit 1
            fi
            path=${S3_BUCKET}
            if [ ! -z "${S3_PATH}" ]; then
                path=$path/${S3_PATH}
            fi
            echo "init default storage volume"
            exec_sql "CREATE STORAGE VOLUME IF NOT EXISTS def_volume TYPE=S3 LOCATIONS=('s3://${path}') PROPERTIES('aws.s3.region'='${S3_REGION}', 'aws.s3.endpoint'='${S3_ENDPOINT}', 'aws.s3.access_key'='${S3_ACCESS_KEY}', 'aws.s3.secret_key'='${S3_SECRET_KEY}');"
            exec_sql "SET def_volume AS DEFAULT STORAGE VOLUME;"
          else
            echo "can not find s3 config, skip init default storage volume"
          fi
  memberLeave:
    customHandler:
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.fe.repository }}:{{ default .Values.image.fe.tag }}
      exec:
        command:
        - /bin/bash
        - -c
        - |
          {{- .Files.Get "scripts/fe-member-leave.sh" | nindent 10 }}
      targetPodSelector: Any
      container: fe
scripts:
- name: scripts
  template: {{ include "starrocks.scriptsTemplate" . }}
  namespace: {{ .Release.Namespace }}
  volumeName: scripts
  defaultMode: 0555
runtime:
  initContainers:
    - name: sysctl-tuner
      command:
      - /bin/bash
      - -c
      - |
        echo "Checking and setting inotify parameters..."
        
        # Check current values
        current_user_instances=$(cat /proc/sys/user/max_inotify_instances 2>/dev/null || echo "0")
        current_fs_instances=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo "0")
        
        echo "Current user.max_inotify_instances: $current_user_instances"
        echo "Current fs.inotify.max_user_instances: $current_fs_instances"
        
        target_value={{ .Values.fe.inotify.maxFsInstances }}
        
        # Set user.max_inotify_instances if current value is less than target
        if [ "$current_user_instances" -lt "$target_value" ]; then
          echo "Setting user.max_inotify_instances to $target_value"
          sysctl -w user.max_inotify_instances=$target_value
        else
          echo "user.max_inotify_instances ($current_user_instances) is already >= $target_value, skipping"
        fi
        
        # Set fs.inotify.max_user_instances if current value is less than target
        if [ "$current_fs_instances" -lt "$target_value" ]; then
          echo "Setting fs.inotify.max_user_instances to $target_value"
          sysctl -w fs.inotify.max_user_instances=$target_value
        else
          echo "fs.inotify.max_user_instances ($current_fs_instances) is already >= $target_value, skipping"
        fi
        
        echo "inotify parameters configuration completed"
      securityContext:
        privileged: true
        runAsUser: 0
  containers:
    - name: fe
      imagePullPolicy: {{ default .Values.image.pullPolicy "IfNotPresent" }}
      command:
      - bash
      - -c
      - |
        /scripts/check-suspend.sh
        {{ if eq .Values.hostType "FQDN" -}}
        /opt/starrocks/fe_entrypoint.sh ${FE_DISCOVERY_ADDR}
        {{- else -}}
        {{ include "POD_IP" . | nindent 8 }}
        /opt/starrocks/fe_entrypoint.sh ${FE_DISCOVERY_ADDR}
        {{- end }}
      ports:
        - containerPort: 8030
          name: http-port
          protocol: TCP
        - containerPort: 9020
          name: rpc-port
          protocol: TCP
        - containerPort: {{ .Values.fe.queryPort }}
          name: query-port
          protocol: TCP
        - containerPort: 9010
          name: edit-log-port
          protocol: TCP
      env:
      {{- include "commonEnvs" . | nindent 6}}
      - name: COMPONENT_NAME
        value: fe
      - name: CONFIGMAP_MOUNT_PATH
        value: /etc/starrocks/fe/conf
      - name: SERVICE_PORT
        value: "8030"
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: false
      livenessProbe:
        failureThreshold: 3
        {{- include "fe.probe" . | nindent 8 }}
      readinessProbe:
        failureThreshold: 3
        {{- include "fe.probe" . | nindent 8 }}
      startupProbe:
        failureThreshold: 60
        {{- include "fe.probe" . | nindent 8 }}
      lifecycle:
        postStart:
          exec:
            command:
            - bash
            - -c
            - |
              /scripts/fe-post-start.sh > /tmp/post-start-hook.log 2>&1
        preStop:
          exec:
            command:
            - bash
            - -c
            - |
              /opt/starrocks/fe_prestop.sh > /tmp/pre-stop-hook.log 2>&1
      volumeMounts:
      - mountPath: /opt/starrocks/fe/meta
        name: data
      - mountPath: /opt/starrocks/fe/conf
        name: fe-cm
      - mountPath: /opt/starrocks/fe/log
        name: log
      - mountPath: /scripts
        name: scripts
      - mountPath: /opt/starrocks/kb/suspend
        name: fe-cm
        subPath: suspend
  volumes:
  - name: log
    emptyDir: {}
{{- end -}}

{{- define "commonEnvs" }}
- name: HOST_TYPE
  {{ if eq .Values.hostType "FQDN" -}}
  value: FQDN
  {{- else -}}
  value: IP
  {{- end }}
- name: IP_FAMILY
  value: {{ .Values.ipFamily }}
- name: TZ
  value: Asia/Shanghai
- name: POD_NAME
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: metadata.name
- name: POD_IP
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: status.podIP
- name: HOST_IP
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: status.hostIP
- name: POD_NAMESPACE
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: metadata.namespace
- name: KB_NAMESPACE
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: metadata.namespace
- name: KB_CLUSTER_COMP_NAME
  value: $(CURRENT_SHARD_COMPONENT_NAME)
{{- end }}

{{- define "params.priority_networks" }}
{{- if .Values.priorityNetworks }}
priority_networks={{ .Values.priorityNetworks }}
{{- else }}
{{- if eq .Values.ipFamily "IPv6" }}
net_use_ipv6_when_priority_networks_empty=true
{{- else }}
net_use_ipv6_when_priority_networks_empty=false
{{- end }}
{{- end }}
{{- end }}

{{/*
Define fe shared data component definition regex pattern
*/}}
{{- define "fe-shared-data.cmpdRegexPattern" -}}
^starrocks-fe-sd-
{{- end -}}

{{/*
Define fe shared nothing component definition regex pattern
*/}}
{{- define "fe-shared-nothing.cmpdRegexPattern" -}}
^starrocks-fe-sn-
{{- end -}}

{{/*
Define cn component definition regex pattern
*/}}
{{- define "cn.cmpdRegexPattern" -}}
^starrocks-cn-
{{- end -}}

{{/*
Define be component definition regex pattern
*/}}
{{- define "be.cmpdRegexPattern" -}}
^starrocks-be-
{{- end -}}

{{/*
Define fe component configuration template name
*/}}
{{- define "fe-shared-data.configTemplate" -}}
starrocks-fe-sd-config-template
{{- end -}}

{{/*
Define fe component configuration template name
*/}}
{{- define "fe-shared-nothing.configTemplate" -}}
starrocks-fe-sn-config-template
{{- end -}}

{{/*
Define cn component configuration template name
*/}}
{{- define "cn.configTemplate" -}}
starrocks-cn-config-template
{{- end -}}

{{/*
Define be component configuration template name
*/}}
{{- define "be.configTemplate" -}}
starrocks-be-config-template
{{- end -}}

{{/*
Define starrocks scripts configMap template name
*/}}
{{- define "starrocks.scriptsTemplate" -}}
starrocks-scripts-template
{{- end -}}

{{/*
Define starrocks parameters definition name
*/}}
{{- define "fe.paramsDefName" -}}
starrocks-fe-pd
{{- end -}}

{{/*
Define starrocks parameters definition name
*/}}
{{- define "be.paramsDefName" -}}
starrocks-be-pd
{{- end -}}

{{/*
Define starrocks parameters definition name
*/}}
{{- define "cn.paramsDefName" -}}
starrocks-cn-pd
{{- end -}}

{{/*
Define starrocks parameters config render name
*/}}
{{- define "fe-shared-data.pcrName" -}}
starrocks-fe-sd-pcr
{{- end -}}

{{/*
Define starrocks parameters config render name
*/}}
{{- define "fe-shared-nothing.pcrName" -}}
starrocks-fe-sn-pcr
{{- end -}}

{{/*
Define starrocks parameters config render name
*/}}
{{- define "cn.pcrName" -}}
starrocks-cn-pcr
{{- end -}}

{{/*
Define starrocks parameters config render name
*/}}
{{- define "be.pcrName" -}}
starrocks-be-pcr
{{- end -}}