{{/*
Expand the name of the chart.
*/}}
{{- define "oceanbase-ce.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "oceanbase-ce.fullname" -}}
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
{{- define "oceanbase-ce.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "oceanbase-ce.labels" -}}
helm.sh/chart: {{ include "oceanbase-ce.chart" . }}
{{ include "oceanbase-ce.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "oceanbase-ce.selectorLabels" -}}
app.kubernetes.io/name: {{ include "oceanbase-ce.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "oceanbase-ce.annotations" -}}
helm.sh/resource-policy: keep
{{- end }}



{{/*
Generate scripts configmap
*/}}
{{- define "oceanbase-ce.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate reloader scripts configmap
*/}}
{{- define "oceanbase-ce.extend.reload.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "reloader/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}


{{- define "oceanbase-ce.compDefName" -}}
oceanbase-ce-{{ .Chart.Version }}
{{- end -}}

{{- define "oceanbase-ce.componentDefNamePrefix" -}}
^oceanbase-ce-
{{- end -}}

{{- define "oceanbase-ce.cc.sysvars" -}}
oceanbase-ce-sysvars-cc
{{- end -}}


{{- define "oceanbase-ce.cc.parameters" -}}
oceanbase-ce-parameters-cc
{{- end -}}


{{- define "oceanbase-ce.clusterDefinition" -}}
oceanbase-ce
{{- end -}}

{{- define "oceanbase-ce.componentVersion" -}}
oceanbase-ce
{{- end -}}

{{- define "oceanbase-ce.backup.actionset" -}}
oceanbase-ce-physical-br
{{- end -}}

{{- define "oceanbase-ce.backup.bpt" -}}
oceanbase-ce-bpt
{{- end -}}


{{- define "oceanbase-ce.cm.config" -}}
oceanbase-ce-config
{{- end -}}

{{- define "oceanbase-ce.cm.sysvars" -}}
oceanbase-ce-sysvars
{{- end -}}

{{- define "oceanbase-ce.scripts.bootscripts" -}}
oceanbase-ce-scripts
{{- end -}}

{{- define "oceanbase-ce.scripts.reload" -}}
oceanbase-ce-reloadscripts
{{- end -}}


{{/*
Define image
*/}}
{{- define "oceanbase-ce.observer.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.observer.repository }}
{{- end -}}

{{- define "oceanbase-ce.metrics.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.metrics.repository }}
{{- end -}}

{{- define "oceanbase-ce.spec.vars" -}}
vars:
- name: OB_ROOT_PASSWD
  valueFrom:
    credentialVarRef:
      name: root
      optional: false
      password: Required
- name: OB_SERVICE_PORT
  value: "2881"
  valueFrom:
    hostNetworkVarRef:
      container:
        name: observer-container
        port:
          name: sql
          option: Optional
      optional: true
- name: OB_RPC_PORT
  value: "2882"
  valueFrom:
    hostNetworkVarRef:
      container:
        name: observer-container
        port:
          name: rpc
          option: Optional
      optional: true
- name: SERVICE_PORT
  value: "8088"
  valueFrom:
    hostNetworkVarRef:
      container:
        name: metrics
        port:
          name: http
          option: Optional
      optional: true
- name: MANAGER_PORT
  value: "8089"
  valueFrom:
    hostNetworkVarRef:
      container:
        name: metrics
        port:
          name: http
          option: Optional
      optional: true
- name: COMP_MYSQL_PORT
  value: $(OB_SERVICE_PORT)
- name: OB_COMPONENT_NAME
  valueFrom:
    componentVarRef:
      optional: false
      componentName: Required
- name: OB_POD_LIST
  valueFrom:
    componentVarRef:
      optional: true
      podNames: Optional
{{- end -}}


{{- define "oceanbase-ce.spec.configs" -}}
configs:
  - name: oceanbase-sysvars
    templateRef: {{ include "oceanbase-ce.cm.sysvars" .}}
    volumeName: oceanbase-sysvars
    constraintRef: {{ include "oceanbase-ce.cc.sysvars" .}}
    namespace: {{ .Release.Namespace }}
    defaultMode: 0555
  - name: oceanbase-config
    templateRef: {{ include "oceanbase-ce.cm.config" .}}
    volumeName: oceanbase-config
    constraintRef: {{ include "oceanbase-ce.cc.parameters" .}}
    namespace: {{ .Release.Namespace }}
    defaultMode: 0555
    reRenderResourceTypes:
      - vscale
scripts:
  - name: oceanbase-scripts
    templateRef: {{ include "oceanbase-ce.scripts.bootscripts" .}}
    namespace: {{ .Release.Namespace }}
    volumeName: scripts
    defaultMode: 0555
{{- end -}}