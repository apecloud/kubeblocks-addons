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
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
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
image: {{ .Values.images.milvus.registry | default ( .Values.images.registry | default "docker.io" ) }}/{{ .Values.images.milvus.repository }}:{{ .Values.images.milvus.tag }}
imagePullPolicy: {{ default "IfNotPresent" .Values.images.pullPolicy }}
{{- end }}

{{/*
Milvus init container - setup
*/}}
{{- define "milvus.initContainer.setup" }}
- name: setup
  image: {{ .Values.images.milvusTools.registry | default ( .Values.images.registry | default "docker.io" ) }}/{{ .Values.images.milvusTools.repository }}:{{ .Values.images.milvusTools.tag }}
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
  templateRef: milvus-config-template-standalone-{{ .Chart.Version }}
  volumeName: milvus-config
  namespace: {{.Release.Namespace}}
  defaultMode: 420
- name: delegate-run
  templateRef: milvus-delegate-run-{{ .Chart.Version }}
  volumeName: milvus-delegate-run
  namespace: {{.Release.Namespace}}
  defaultMode: 493
{{- end }}

{{/*
Milvus user config - cluster
*/}}
{{- define "milvus.config.cluster" }}
- name: config
  templateRef: milvus-config-template-cluster-{{ .Chart.Version }}
  volumeName: milvus-config
  namespace: {{.Release.Namespace}}
  defaultMode: 420
- name: delegate-run
  templateRef: milvus-delegate-run-{{ .Chart.Version }}
  volumeName: milvus-delegate-run
  namespace: {{.Release.Namespace}}
  defaultMode: 493
{{- end }}

{{/*
Milvus monitor
*/}}
{{- define "milvus.monitor" }}
# builtIn: false
# exporterConfig:
#   scrapePath: /metrics
#   scrapePort: 9091
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
