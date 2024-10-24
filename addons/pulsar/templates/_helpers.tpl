{{/*
Expand the name of the chart.
*/}}
{{- define "pulsar.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pulsar.fullname" -}}
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
{{- define "pulsar.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pulsar.labels" -}}
helm.sh/chart: {{ include "pulsar.chart" . }}
{{ include "pulsar.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pulsar.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pulsar.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "pulsar.annotations" -}}
helm.sh/resource-policy: keep
{{- end }}

{{/*
Create full image name
*/}}
{{- define "pulsar.imageFullName" -}}
{{- printf "%s/%s:%s" ( .image.registry | default .root.Values.image.registry ) (  .image.repository | default .root.Values.image.repository ) ( .image.tag | default .root.Values.image.tag | default .root.Chart.AppVersion ) -}}
{{- end -}}

{{/*
Create image pull policy
*/}}
{{- define "pulsar.imagePullPolicy" -}}
{{- printf "%s" ( .image.pullPolicy | default .root.Values.image.pullPolicy | default "IfNotPresent" ) -}}
{{- end -}}

{{/*
Generate scripts configmap
*/}}
{{- define "pulsar.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate major version of cluster
*/}}
{{- define "pulsar.major.version" -}}
{{- $version := default .Chart.AppVersion .Values.clusterVersionOverride -}}
{{- $majorVersion := (split "." $version)._0 -}}
{{- printf "%s" ($majorVersion)}}
{{- end }}

{{/*
Define pulsar bookies recovery component definition regex pattern
*/}}
{{- define "pulsar.bkRecoveryCmpdRegexPattern" -}}
^pulsar-bookies-recovery-
{{- end -}}

{{/*
Define pulsar v3.X bookies recovery component definition name
*/}}
{{- define "pulsar3.bkRecoveryCmpdName" -}}
pulsar-bookies-recovery-3-{{ .Chart.Version }}
{{- end -}}

{{/*
Define pulsar v2.X bookies recovery component definition name
*/}}
{{- define "pulsar2.bkRecoveryCmpdName" -}}
pulsar-bookies-recovery-2-{{ .Chart.Version }}
{{- end -}}

{{/*
Define pulsar bookkeeper component definition regex pattern
*/}}
{{- define "pulsar.bookkeeperCmpdRegexPattern" -}}
^pulsar-bookkeeper-
{{- end -}}

{{/*
Define pulsar v3.X bookkeeper component definition name
*/}}
{{- define "pulsar3.bookkeeperCmpdName" -}}
pulsar-bookkeeper-3-{{ .Chart.Version }}
{{- end -}}

{{/*
Define pulsar v2.X bookkeeper component definition name
*/}}
{{- define "pulsar2.bookkeeperCmpdName" -}}
pulsar-bookkeeper-2-{{ .Chart.Version }}
{{- end -}}

{{/*
Define pulsar broker component definition regex pattern
*/}}
{{- define "pulsar.brokerCmpdRegexPattern" -}}
^pulsar-broker-
{{- end -}}

{{/*
Define pulsar v3.X broker component definition name
*/}}
{{- define "pulsar3.brokerCmpdName" -}}
pulsar-broker-3-{{ .Chart.Version }}
{{- end -}}

{{/*
Define pulsar v3.X broker component definition regex pattern
*/}}
{{- define "pulsar3.brokerCmpdRegexPattern" -}}
^pulsar-broker-3-
{{- end -}}

{{/*
Define pulsar v2.X broker component definition name
*/}}
{{- define "pulsar2.brokerCmpdName" -}}
pulsar-broker-2-{{ .Chart.Version }}
{{- end -}}

{{/*
Define pulsar v2.X broker component definition regex pattern
*/}}
{{- define "pulsar2.brokerCmpdRegexPattern" -}}
^pulsar-broker-2-
{{- end -}}

{{/*
Define pulsar proxy component definition regex pattern
*/}}
{{- define "pulsar.proxyCmpdRegexPattern" -}}
^pulsar-proxy-
{{- end -}}

{{/*
Define pulsar v3.X proxy component definition name
*/}}
{{- define "pulsar3.proxyCmpdName" -}}
pulsar-proxy-3-{{ .Chart.Version }}
{{- end -}}

{{/*
Define pulsar v2.X proxy component definition name
*/}}
{{- define "pulsar2.proxyCmpdName" -}}
pulsar-proxy-2-{{ .Chart.Version }}
{{- end -}}

{{/*
Define pulsar zookeeper component definition regex pattern
*/}}
{{- define "pulsar.zookeeperCmpdRegexPattern" -}}
^pulsar-zookeeper-
{{- end -}}

{{/*
Define pulsar v3.X zookeeper component definition name
*/}}
{{- define "pulsar3.zookeeperCmpdName" -}}
pulsar-zookeeper-3-{{ .Chart.Version }}
{{- end -}}

{{/*
Define pulsar v2.X zookeeper component definition name
*/}}
{{- define "pulsar2.zookeeperCmpdName" -}}
pulsar-zookeeper-2-{{ .Chart.Version }}
{{- end -}}

{{/*
Define pulsar scripts tpl name
*/}}
{{- define "pulsar.scriptsTplName" -}}
pulsar-scripts
{{- end -}}

{{/*
Define pulsar tools scripts tpl name
*/}}
{{- define "pulsar.toolsScriptsTplName" -}}
pulsar-tools-script
{{- end -}}

{{/*
Define pulsar bookies recovery env tpl name
*/}}
{{- define "pulsar.bookiesRecoveryEnvTplName" -}}
pulsar-bookies-recovery-env-tpl
{{- end -}}

{{/*
Define pulsar bookies recovery env tpl name
*/}}
{{- define "pulsar.bookiesEnvTplName" -}}
pulsar-bookies-env-tpl
{{- end -}}

{{/*
Define pulsar broker env tpl name
*/}}
{{- define "pulsar.brokerEnvTplName" -}}
pulsar-broker-env-tpl
{{- end -}}

{{/*
Define pulsar proxy env tpl name
*/}}
{{- define "pulsar.proxyEnvTplName" -}}
pulsar-proxy-env-tpl
{{- end -}}

{{/*
Define pulsar zookeeper env tpl name
*/}}
{{- define "pulsar.zookeeperEnvTplName" -}}
pulsar-zookeeper-env-tpl
{{- end -}}

{{/*
Define pulsar env config constraint name
*/}}
{{- define "pulsar.envConstraintName" -}}
pulsar-env-constraints
{{- end -}}

{{/*
Define pulsar v3.X bookies config tpl name
*/}}
{{- define "pulsar3.bookiesConfigTplName" -}}
pulsar3-bookies-config-tpl
{{- end -}}

{{/*
Define pulsar v2.X bookies config tpl name
*/}}
{{- define "pulsar2.bookiesConfigTplName" -}}
pulsar2-bookies-config-tpl
{{- end -}}

{{/*
Define pulsar v3.X bookies config constraint name
*/}}
{{- define "pulsar3.bookiesConfigConstraintName" -}}
pulsar3-bookies-config-constraint
{{- end -}}

{{/*
Define pulsar v2.X bookies config constraint name
*/}}
{{- define "pulsar2.bookiesConfigConstraintName" -}}
pulsar2-bookies-config-constraint
{{- end -}}

{{/*
Define pulsar v3.X broker config tpl name
*/}}
{{- define "pulsar3.brokerConfigTplName" -}}
pulsar3-broker-config-tpl
{{- end -}}

{{/*
Define pulsar v2.X broker config tpl name
*/}}
{{- define "pulsar2.brokerConfigTplName" -}}
pulsar2-broker-config-tpl
{{- end -}}

{{/*
Define pulsar v3.X broker config constraint name
*/}}
{{- define "pulsar3.brokerConfigConstraintName" -}}
pulsar3-broker-config-constraint
{{- end -}}

{{/*
Define pulsar v2.X broker config constraint name
*/}}
{{- define "pulsar2.brokerConfigConstraintName" -}}
pulsar2-broker-config-constraint
{{- end -}}

{{/*
Define pulsar v3.X proxy config tpl name
*/}}
{{- define "pulsar3.proxyConfigTplName" -}}
pulsar3-proxy-config-tpl
{{- end -}}

{{/*
Define pulsar v2.X broker config tpl name
*/}}
{{- define "pulsar2.proxyConfigTplName" -}}
pulsar2-proxy-config-tpl
{{- end -}}

{{/*
Define pulsar v3.X proxy config constraint name
*/}}
{{- define "pulsar3.proxyConfigConstraintName" -}}
pulsar3-proxy-config-constraint
{{- end -}}

{{/*
Define pulsar v2.X proxy config constraint name
*/}}
{{- define "pulsar2.proxyConfigConstraintName" -}}
pulsar2-proxy-config-constraint
{{- end -}}

{{/*
Define pulsar v3.X bookies image
*/}}
{{- define "pulsar3.bookiesImage" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.images.v3_0_2.bookie.tag }}
{{- end }}

{{/*
Define pulsar v2.X bookies image
*/}}
{{- define "pulsar2.bookiesImage" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.images.v2_11_2.bookie.tag }}
{{- end }}

{{/*
Define pulsar v3.X broker image
*/}}
{{- define "pulsar3.brokerImage" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.images.v3_0_2.broker.tag }}
{{- end }}

{{/*
Define pulsar v2.X broker image
*/}}
{{- define "pulsar2.brokerImage" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.images.v2_11_2.broker.tag }}
{{- end }}

{{/*
Define pulsar v3.X proxy image
*/}}
{{- define "pulsar3.proxyImage" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.images.v3_0_2.proxy.tag }}
{{- end }}

{{/*
Define pulsar v2.X proxy image
*/}}
{{- define "pulsar2.proxyImage" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.images.v2_11_2.proxy.tag }}
{{- end }}

{{/*
Define pulsar v3.X zookeeper image
*/}}
{{- define "pulsar3.zookeeperImage" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.images.v3_0_2.zookeeper.tag }}
{{- end }}

{{/*
Define pulsar v2.X zookeeper image
*/}}
{{- define "pulsar2.zookeeperImage" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.images.v2_11_2.zookeeper.tag }}
{{- end }}