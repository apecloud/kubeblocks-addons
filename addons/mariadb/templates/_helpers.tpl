{{/*
Expand the name of the chart.
*/}}
{{- define "mariadb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mariadb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mariadb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mariadb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mariadb.labels" -}}
helm.sh/chart: {{ include "mariadb.chart" . }}
{{ include "mariadb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Define image
*/}}
{{- define "mariadb.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "mariadb.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}

{{- define "exporter.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.prom.exporter.repository}}
{{- end }}

{{- define "exporter.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.prom.exporter.repository}}:{{.Values.image.prom.exporter.tag}}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "mariadb.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "mariadb.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "mariadb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define mariadb component definition name
*/}}
{{- define "mariadb.cmpdName" -}}
mariadb-{{ .Chart.Version }}
{{- end -}}

{{/*
Define mariadb-replication component definition name
*/}}
{{- define "mariadb.replication.cmpdName" -}}
mariadb-replication-{{ .Chart.Version }}
{{- end -}}

{{/*
Define mariadb-galera component definition name
*/}}
{{- define "mariadb.galera.cmpdName" -}}
mariadb-galera-{{ .Chart.Version }}
{{- end -}}

{{/*
Define mariadb component definition regular expression name prefix
*/}}
{{- define "mariadb.cmpdRegexpPattern" -}}
^mariadb-
{{- end -}}

{{/*
Define mariadb-replication component definition regular expression name prefix
*/}}
{{- define "mariadb.replication.cmpdRegexpPattern" -}}
^mariadb-replication-
{{- end -}}

{{/*
Define mariadb-galera component definition regular expression name prefix
*/}}
{{- define "mariadb.galera.cmpdRegexpPattern" -}}
^mariadb-galera-
{{- end -}}

{{/*
Syncer image
*/}}
{{- define "mariadb.syncer.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.syncer.repository }}:{{ .Values.image.syncer.tag }}
{{- end -}}

{{/*
Common spec for replication and galera: accounts, exporter, volumes
*/}}
{{- define "mariadb.spec.systemAccounts" -}}
systemAccounts:
  - name: root
    initAccount: true
    passwordGenerationPolicy:
      length: 10
      numDigits: 3
      numSymbols: 4
      letterCase: MixedCases
{{- end -}}

{{/*
Common vars for replication and galera
*/}}
{{- define "mariadb.spec.vars" -}}
vars:
  - name: MARIADB_ROOT_USER
    valueFrom:
      credentialVarRef:
        name: root
        optional: false
        username: Required
  - name: MARIADB_ROOT_PASSWORD
    valueFrom:
      credentialVarRef:
        name: root
        optional: false
        password: Required
  - name: CLUSTER_NAME
    valueFrom:
      clusterVarRef:
        clusterName: Required
  - name: CLUSTER_NAMESPACE
    valueFrom:
      clusterVarRef:
        namespace: Required
  - name: COMPONENT_NAME
    valueFrom:
      componentVarRef:
        optional: false
        shortName: Required
{{- end -}}

{{/*
Exporter container
*/}}
{{- define "mariadb.container.exporter" -}}
- name: exporter
  imagePullPolicy: {{ default "IfNotPresent" .Values.image.prom.pullPolicy }}
  ports:
    - name: metrics
      containerPort: 9104
      protocol: TCP
  env:
    - name: DATA_SOURCE_NAME
      value: "$(MARIADB_ROOT_USER):$(MARIADB_ROOT_PASSWORD)@(localhost:3306)/"
{{- end -}}
