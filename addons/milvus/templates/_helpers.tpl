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
Create the name of the service account to use

{{- define "milvus.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "milvus.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "milvus.checkerServiceAccountName" -}}
{{- if .Values.installDependencies.enable }}
{{- if .Values.installDependencies.serviceAccount.create }}
{{- default (printf "%s-checker" (include "milvus.fullname" .)) .Values.installDependencies.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
{{- end }}
*/}}

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
Milvus cluster default config
*/}}
{{- define "milvus.cluster.config" }}
- name: milvus-config
  templateRef: milvus-config-template
  volumeName: milvus-config
  namespace: {{.Release.Namespace}}
  defaultMode: 420
{{- end }}

{{/*
Milvus cluster monitor
*/}}
{{- define "milvus.cluster.monitor" }}
monitor:
  builtIn: false
  exporterConfig:
    scrapePath: /metrics
    scrapePort: 9091
{{- end }}

{{/*
Milvus cluster init container - config
*/}}
{{- define "milvus.cluster.initContainer.config" }}
- name: config
  image: {{ .Values.images.milvusTools.repository }}:{{ .Values.images.milvusTools.tag }}
  imagePullPolicy: {{ default .Values.images.pullPolicy "IfNotPresent" }}
  command:
    - /cp
    - /run.sh,/merge
    - /milvus/tools/run.sh,/milvus/tools/merge
  volumeMounts:
    - mountPath: /milvus/tools
      name: milvus-tools
{{- end }}

{{/*
Milvus cluster image
*/}}
{{- define "milvus.cluster.image" }}
image: {{ .Values.images.milvus.repository }}:{{ .Values.images.milvus.tag }}
imagePullPolicy: {{ default .Values.images.pullPolicy "IfNotPresent" }}
{{- end }}

{{/*
Milvus cluster default env
*/}}
{{- define "milvus.cluster.env.default" }}
- name: CACHE_SIZE
  valueFrom:
    resourceFieldRef:
      divisor: 1Gi
      resource: limits.memory
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
Milvus cluster default volume mounts
*/}}
{{- define "milvus.cluster.volumeMount.default" }}
- mountPath: /milvus/configs/user.yaml
  name: milvus-config
  readOnly: true
  subPath: user.yaml
- mountPath: /milvus/tools
  name: milvus-tools
{{- end }}

{{/*
Milvus cluster default volumes
*/}}
{{- define "milvus.cluster.volume.default" }}
- name: milvus-tools
  emptyDir: {}
{{- end }}

{{/*
Milvus cluster metric container port
*/}}
{{- define "milvus.cluster.containerPort.metric" }}
- containerPort: 9091
  name: metrics
  protocol: TCP
{{- end }}

{{/*
Milvus cluster external storage services reference
*/}}
{{- define "milvus.cluster.storageServiceRef" }}
serviceRefDeclarations:
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
        serviceVersion: "*"
{{- end }}