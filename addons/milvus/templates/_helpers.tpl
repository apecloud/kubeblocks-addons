{{/*
Expand the name of the chart.
*/}}
{{- define "milvus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "milvus.fullname" -}}
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
{{- define "milvus.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "milvus.labels" -}}
helm.sh/chart: {{ include "milvus.chart" . }}
{{ include "milvus.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "milvus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "milvus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "milvus.annotations" -}}
helm.sh/resource-policy: keep
{{- end }}

{{/*
Define milvus standalone component definition name
*/}}
{{- define "milvus-standalone.cmpdName" -}}
milvus-standalone-{{ .Chart.Version }}
{{- end -}}

{{/*
Define milvus standalone component definition regex pattern
*/}}
{{- define "milvus-standalone.cmpdRegexpPattern" -}}
^milvus-standalone-
{{- end -}}

{{/*
Define milvus minio component definition name
*/}}
{{- define "milvus-minio.cmpdName" -}}
milvus-minio-{{ .Chart.Version }}
{{- end -}}

{{/*
Define milvus minio component definition regex pattern
*/}}
{{- define "milvus-minio.cmpdRegexpPattern" -}}
^milvus-minio-
{{- end -}}

{{/*
Define milvus datanode component definition name
*/}}
{{- define "milvus-datanode.cmpdName" -}}
milvus-datanode-{{ .Chart.Version }}
{{- end -}}

{{/*
Define milvus datanode component definition regex pattern
*/}}
{{- define "milvus-datanode.cmpdRegexpPattern" -}}
^milvus-datanode-
{{- end -}}

{{/*
Define milvus indexnode component definition name
*/}}
{{- define "milvus-indexnode.cmpdName" -}}
milvus-indexnode-{{ .Chart.Version }}
{{- end -}}

{{/*
Define milvus indexnode component definition regex pattern
*/}}
{{- define "milvus-indexnode.cmpdRegexpPattern" -}}
^milvus-indexnode-
{{- end -}}

{{/*
Define milvus mixcoord component definition name
*/}}
{{- define "milvus-mixcoord.cmpdName" -}}
milvus-mixcoord-{{ .Chart.Version }}
{{- end -}}

{{/*
Define milvus mixcoord component definition regex pattern
*/}}
{{- define "milvus-mixcoord.cmpdRegexpPattern" -}}
^milvus-mixcoord-
{{- end -}}

{{/*
Define milvus proxy component definition name
*/}}
{{- define "milvus-proxy.cmpdName" -}}
milvus-proxy-{{ .Chart.Version }}
{{- end -}}

{{/*
Define milvus proxy component definition regex pattern
*/}}
{{- define "milvus-proxy.cmpdRegexpPattern" -}}
^milvus-proxy-
{{- end -}}

{{/*
Define milvus querynode component definition name
*/}}
{{- define "milvus-querynode.cmpdName" -}}
milvus-querynode-{{ .Chart.Version }}
{{- end -}}

{{/*
Define milvus querynode component definition regex pattern
*/}}
{{- define "milvus-querynode.cmpdRegexpPattern" -}}
^milvus-querynode-
{{- end -}}

{{/*
Define milvus etcd component definition regex pattern
*/}}
{{- define "milvus-etcd.cmpdRegexpPattern" -}}
^etcd-
{{- end -}}

{{/*
Define milvus standalone configuration template name
*/}}
{{- define "milvus-standalone.configTemplateName" -}}
milvus-config-template-standalone-{{ .Chart.Version }}
{{- end -}}

{{/*
Define milvus cluster configuration template name
*/}}
{{- define "milvus-cluster.configTemplateName" -}}
milvus-config-template-cluster-{{ .Chart.Version }}
{{- end -}}

{{/*
Define milvus delegate run configuration template name
*/}}
{{- define "milvus-delegate-run.configTemplateName" -}}
milvus-delegate-run-{{ .Chart.Version }}
{{- end -}}

{{/*
Startup probe
*/}}
{{- define "milvus.probe.startup" }}
{{- if .Values.startupProbe.enabled }}
startupProbe:
  httpGet:
    path: /healthz
    port: metrics
    scheme: HTTP
  initialDelaySeconds: {{ .Values.startupProbe.initialDelaySeconds }}
  periodSeconds: {{ .Values.startupProbe.periodSeconds }}
  timeoutSeconds: {{ .Values.startupProbe.timeoutSeconds }}
  successThreshold: {{ .Values.startupProbe.successThreshold }}
  failureThreshold: {{ .Values.startupProbe.failureThreshold }}
{{- end }}
{{- end }}

{{/*
Liveness probe
*/}}
{{- define "milvus.probe.liveness" }}
{{- if .Values.livenessProbe.enabled }}
livenessProbe:
  httpGet:
    path: /healthz
    port: metrics
    scheme: HTTP
  initialDelaySeconds: {{ .Values.livenessProbe.initialDelaySeconds }}
  periodSeconds: {{ .Values.livenessProbe.periodSeconds }}
  timeoutSeconds: {{ .Values.livenessProbe.timeoutSeconds }}
  successThreshold: {{ .Values.livenessProbe.successThreshold }}
  failureThreshold: {{ .Values.livenessProbe.failureThreshold }}
{{- end }}
{{- end }}

{{/*
Readiness probe
*/}}
{{- define "milvus.probe.readiness" }}
{{- if .Values.readinessProbe.enabled }}
readinessProbe:
  httpGet:
    path: /healthz
    port: metrics
    scheme: HTTP
  initialDelaySeconds: {{ .Values.readinessProbe.initialDelaySeconds }}
  periodSeconds: {{ .Values.readinessProbe.periodSeconds }}
  timeoutSeconds: {{ .Values.readinessProbe.timeoutSeconds }}
  successThreshold: {{ .Values.readinessProbe.successThreshold }}
  failureThreshold: {{ .Values.readinessProbe.failureThreshold }}
{{- end }}
{{- end }}

{{/*
Milvus image
*/}}
{{- define "milvus.image" }}
imagePullPolicy: {{ default "IfNotPresent" .Values.images.pullPolicy }}
{{- end }}

{{/*
Milvus init container - setup
*/}}
{{- define "milvus.initContainer.setup" }}
- name: setup
  imagePullPolicy: {{ default "IfNotPresent" .Values.images.pullPolicy }}
  command:
    - /cp
    - /run.sh,/merge
    - /milvus/tools/run.sh,/milvus/tools/merge
  volumeMounts:
    {{- include "milvus.volumeMount.tools" . | indent 4 }}
{{- end }}

{{/*
Milvus env - cache size
*/}}
{{- define "milvus.env.cacheSize" }}
- name: CACHE_SIZE
  valueFrom:
    resourceFieldRef:
      divisor: 1Gi
      resource: limits.memory
{{- end }}

{{/*
Milvus env - minio ak/sk
*/}}
{{- define "milvus.env.minio" }}
- name: MINIO_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      key: accesskey
      name: $(CONN_CREDENTIAL_SECRET_NAME)  # TODO: minio ak/sk secret
- name: MINIO_SECRET_KEY
  valueFrom:
    secretKeyRef:
      key: secretkey
      name: $(CONN_CREDENTIAL_SECRET_NAME)  # TODO: minio ak/sk secret
{{- end }}

{{/*
Milvus container port - milvus
*/}}
{{- define "milvus.containerPort.milvus" }}
- containerPort: 19530
  name: milvus
  protocol: TCP
{{- end }}

{{/*
Milvus container port - metric
*/}}
{{- define "milvus.containerPort.metric" }}
- containerPort: 9091
  name: metrics
  protocol: TCP
{{- end }}

{{/*
Milvus volume mounts - data
*/}}
{{- define "milvus.volumeMount.data" }}
- mountPath: /var/lib/milvus
  name: data
{{- end }}

{{/*
Milvus volume mounts - tools
*/}}
{{- define "milvus.volumeMount.tools" }}
- mountPath: /milvus/tools
  name: milvus-tools
{{- end }}

{{/*
Milvus volume mounts - user
*/}}
{{- define "milvus.volumeMount.user" }}
- mountPath: /milvus/configs/user.yaml.raw
  name: milvus-config
  readOnly: true
  subPath: user.yaml
- mountPath: /milvus/tools/delegate-run.sh
  name: milvus-delegate-run
  readOnly: true
  subPath: delegate-run.sh
{{- end }}

{{/*
Milvus tools volume
*/}}
{{- define "milvus.volume.tools" }}
- name: milvus-tools
  emptyDir: {}
{{- end }}

{{/*
Milvus user config - standalone
*/}}
{{- define "milvus.config.standalone" }}
- name: config
  templateRef: {{ include "milvus-standalone.configTemplateName" . }}
  volumeName: milvus-config
  namespace: {{.Release.Namespace}}
  defaultMode: 420
- name: delegate-run
  templateRef: {{ include "milvus-delegate-run.configTemplateName" . }}
  volumeName: milvus-delegate-run
  namespace: {{.Release.Namespace}}
  defaultMode: 493
{{- end }}

{{/*
Milvus user config - cluster
*/}}
{{- define "milvus.config.cluster" }}
- name: config
  templateRef: {{ include "milvus-cluster.configTemplateName" . }}
  volumeName: milvus-config
  namespace: {{.Release.Namespace}}
  defaultMode: 420
- name: delegate-run
  templateRef: {{ include "milvus-delegate-run.configTemplateName" . }}
  volumeName: milvus-delegate-run
  namespace: {{.Release.Namespace}}
  defaultMode: 493
{{- end }}

{{/*
Milvus cluster external storage services reference
*/}}
{{- define "milvus.cluster.serviceRef" }}
- name: milvus-meta-storage
  serviceRefDeclarationSpecs:
    - serviceKind: etcd
      serviceVersion: "^3.*"
- name: milvus-log-storage
  serviceRefDeclarationSpecs:
    - serviceKind: pulsar
      serviceVersion: "^2.*"
- name: milvus-object-storage
  serviceRefDeclarationSpecs:
    - serviceKind: minio
      serviceVersion: "^*"
{{- end }}

{{/*
Milvus cluster vars for external storage services reference
*/}}
{{- define "milvus.cluster.serviceRefVars" }}
- name: ETCD_ENDPOINT
  valueFrom:
    serviceRefVarRef:
      name: milvus-meta-storage
      optional: false
      endpoint: Required
  expression: {{ `{{ index (splitList ":" .ETCD_ENDPOINT) 0 }}:{{ .ETCD_PORT }}` | toYaml }}
- name: ETCD_PORT
  valueFrom:
    serviceRefVarRef:
      name: milvus-meta-storage
      optional: false
      port: Required
- name: MINIO_SERVER
  valueFrom:
    serviceRefVarRef:
      name: milvus-object-storage
      optional: false
      endpoint: Required
- name: MINIO_PORT
  valueFrom:
    serviceRefVarRef:
      name: milvus-object-storage
      optional: false
      port: Required
- name: MINIO_ACCESS_KEY
  valueFrom:
    serviceRefVarRef:
      name: milvus-object-storage
      optional: false
      username: Required
- name: MINIO_SECRET_KEY
  valueFrom:
    serviceRefVarRef:
      name: milvus-object-storage
      optional: false
      password: Required
- name: PULSAR_SERVER
  valueFrom:
    serviceRefVarRef:
      name: milvus-log-storage
      optional: false
      endpoint: Required
  expression: {{ `{{ index (splitList ":" .PULSAR_SERVER) 0 }}` | toYaml }}
- name: PULSAR_PORT
  valueFrom:
    serviceRefVarRef:
      name: milvus-log-storage
      optional: false
      port: Required
{{- end }}
