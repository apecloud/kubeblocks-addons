{{/*
Expand the name of the chart.
*/}}
{{- define "elasticsearch.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "elasticsearch.fullname" -}}
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
{{- define "elasticsearch.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "elasticsearch.labels" -}}
helm.sh/chart: {{ include "elasticsearch.chart" . }}
{{ include "elasticsearch.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "elasticsearch.selectorLabels" -}}
app.kubernetes.io/name: {{ include "elasticsearch.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "elasticsearch.annotations" -}}
helm.sh/resource-policy: keep
{{ include "elasticsearch.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "elasticsearch.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{- define "elasticsearch.cmpdRegexPattern" -}}
^elasticsearch-
{{- end -}}

{{- define "elasticsearch7.cmpdName" -}}
elasticsearch-7-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearchMaster7.cmpdName" -}}
elasticsearch-master-7-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearchData7.cmpdName" -}}
elasticsearch-data-7-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearch7.cmpdRegexPattern" -}}
^elasticsearch-7-
{{- end -}}

{{- define "elasticsearchMaster7.cmpdRegexPattern" -}}
^elasticsearch-master-7-
{{- end -}}

{{- define "elasticsearchData7.cmpdRegexPattern" -}}
^elasticsearch-data-7-
{{- end -}}

{{- define "elasticsearch8.cmpdName" -}}
elasticsearch-8-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearchMaster8.cmpdName" -}}
elasticsearch-master-8-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearchData8.cmpdName" -}}
elasticsearch-data-8-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearch8.cmpdRegexPattern" -}}
^elasticsearch-8-
{{- end -}}

{{- define "elasticsearchMaster8.cmpdRegexPattern" -}}
^elasticsearch-master-8-
{{- end -}}

{{- define "elasticsearchData8.cmpdRegexPattern" -}}
^elasticsearch-data-8-
{{- end -}}

{{- define "elasticsearch.scriptsTplName" -}}
elasticsearch-scripts-tpl
{{- end -}}

{{- define "elasticsearch7.configTplName" -}}
elasticsearch-7-config-tpl
{{- end -}}

{{- define "elasticsearch8.configTplName" -}}
elasticsearch-8-config-tpl
{{- end -}}

{{- define "elasticsearch-8.1.3.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:8.1.3
{{- end }}

{{- define "elasticsearch-8.8.2.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:8.8.2
{{- end }}

{{- define "elasticsearch-8.15.5.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:8.15.5
{{- end }}

{{- define "elasticsearch-7.10.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:7.10.1
{{- end }}

{{- define "elasticsearch-7.7.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:7.7.1
{{- end }}

{{- define "elasticsearch-7.8.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:7.8.1
{{- end }}

{{- define "elasticsearch-exporter.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.exporter.repository }}:{{ .Values.image.exporter.tag | default "latest" }}
{{- end }}

{{- define "elasticsearch-lfa.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.tools.repository }}:{{ .Values.image.tools.tag | default "latest" }}
{{- end }}

{{/*
Define elasticsearch v7.X parameter config renderer name
*/}}
{{- define "elasticsearch7.pcrName" -}}
elasticsearch7-pcr
{{- end }}

{{/*
Define elasticsearch v8.X parameter config renderer name
*/}}
{{- define "elasticsearch8.pcrName" -}}
elasticsearch8-pcr
{{- end }}

{{/*
Define kibana v8.X component definition name
*/}}
{{- define "kibana8.cmpdName" -}}
kibana-8-{{ .Chart.Version }}
{{- end -}}

{{/*
Define kibana v8.X component definition regex pattern
*/}}
{{- define "kibana8.cmpdRegexPattern" -}}
^kibana-8-
{{- end -}}

{{/*
Define kibana component definition regex pattern
*/}}
{{- define "kibana.cmpdRegexPattern" -}}
^kibana-
{{- end -}}

{{/*
Define kibana v7.X component definition name
*/}}
{{- define "kibana7.cmpdName" -}}
kibana-7-{{ .Chart.Version }}
{{- end -}}

{{/*
Define kibana v7.X component definition regex pattern
*/}}
{{- define "kibana7.cmpdRegexPattern" -}}
^kibana-7-
{{- end -}}

{{/*
Define kibana config tpl name
*/}}
{{- define "kibana.configTplName" -}}
kibana-config-tpl
{{- end -}}

{{- define "kibana-7.7.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:7.7.1
{{- end }}

{{- define "kibana-7.8.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:7.8.1
{{- end }}

{{- define "kibana-7.10.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:7.10.1
{{- end }}

{{- define "kibana-8.1.3.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:8.1.3
{{- end }}

{{- define "kibana-8.8.2.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:8.8.2
{{- end }}

{{- define "kibana-8.15.5.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:8.15.5
{{- end }}

{{- define "kibana-8.9.1.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.kibana.repository }}:8.9.1
{{- end }}

{{- define "elasticsearch-agent.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.agent.repository }}:0.1.0
{{- end }}

{{- define "elasticsearch.common" }}
provider: kubeblocks
description: Elasticsearch is a distributed, restful search engine optimized for speed and relevance on production-scale workloads.
serviceKind: elasticsearch
updateStrategy: Parallel
podManagementPolicy: Parallel
configs:
  - name: es-cm
    template: {{ include "elasticsearch8.configTplName" . }}
    namespace: {{ .Release.Namespace }}
    volumeName: es-cm
    restartOnFileChange: true
exporter:
  containerName: exporter
  scrapePath: /metrics
  scrapePort: {{ .Values.exporter.service.port | quote}}
tls:
  volumeName: tls
  mountPath: /etc/pki/tls
  caFile: ca.pem
  certFile: cert.pem
  keyFile: key.pem
scripts:
  - name: scripts
    template: {{ include "elasticsearch.scriptsTplName" . }}
    namespace: {{ .Release.Namespace }}
    volumeName: scripts
    defaultMode: 0555
services:
  - name: http
    serviceName: http
    spec:
      ipFamilyPolicy: PreferDualStack
      ipFamilies:
        - IPv4
      ports:
        - name: http
          port: 9200
          targetPort: http
  - name: agent
    serviceName: agent
    spec:
      ipFamilyPolicy: PreferDualStack
      ipFamilies:
      - IPv4
      ports:
      - name: agent
        port: 8080
        targetPort: agent            
systemAccounts:
- name: elastic
  initAccount: true
  passwordGenerationPolicy:
    length: 10
    numDigits: 5
    numSymbols: 0
    letterCase: MixedCases
- name: kibana_system
  initAccount: true
  passwordGenerationPolicy:
    length: 10
    numDigits: 5
    numSymbols: 0
    letterCase: MixedCases
lifecycleActions:
  memberLeave:
    exec:
      command:
        - /bin/sh
        - -c
        - /mnt/remote-scripts/member-leave.sh
      targetPodSelector: Any
      container: elasticsearch
runtime:
  initContainers:
    - name: prepare-plugins
      imagePullPolicy: IfNotPresent
      command:
        - sh
        - -c
        - |
          if [ -d /plugins ]; then
            echo "install plugins: $(ls /plugins)"
            cp -r /plugins/* /tmp/plugins/
          else
            echo "there is no plugins"
          fi
      securityContext:
        runAsUser: 0
        privileged: true
      volumeMounts:
        - mountPath: /tmp/plugins
          name: plugins
    - name: install-plugins
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      command:
        - sh
        - -c
        - |
          set -x
          sh /mnt/remote-scripts/install-plugins.sh
          sh /mnt/remote-scripts/prepare-fs.sh
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        privileged: false
        runAsNonRoot: true
        runAsUser: 1000
      volumeMounts:
        - mountPath: /mnt/remote-config
          name: es-cm
          readOnly: true
        - mountPath: /mnt/remote-scripts
          name: scripts
          readOnly: true
        - mountPath: /mnt/local-bin
          name: local-bin
        - mountPath: /mnt/local-config
          name: local-config
        - mountPath: /mnt/local-plugins
          name: local-plugins
        - mountPath: /tmp/plugins
          name: plugins
    - name: install-es-agent
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      command:
        - sh
        - -c
        - |
          cp /usr/local/bin/agent /mnt/local-bin/es-agent
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        privileged: false
        runAsNonRoot: true
        runAsUser: 1000
      volumeMounts:
        - mountPath: /mnt/local-bin
          name: local-bin
  containers:
    - name: elasticsearch
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      command:
        - sh
        - -c
        - |
          cp /etc/pki/tls/* /usr/share/elasticsearch/config/
          # remove initial master nodes block if cluster has been formed
          if [ -f "${CLUSTER_FORMED_FILE}" ]; then
            sed -i '/# INITIAL_MASTER_NODES_BLOCK_START/,/# INITIAL_MASTER_NODES_BLOCK_END/d' config/elasticsearch.yml
          fi
          if [ -f /bin/tini ]; then
            /bin/tini -- /usr/local/bin/docker-entrypoint.sh
          else
            /tini -- /usr/local/bin/docker-entrypoint.sh
          fi

      env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: status.podIP
        - name: POD_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.name
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: spec.nodeName
        - name: KB_NAMESPACE
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
        - name: POD_FQDN
          value: $(POD_NAME).$(ES_COMPONENT_NAME)-headless.$(KB_NAMESPACE).svc.$(CLUSTER_DOMAIN)
        - name: READINESS_PROBE_PROTOCOL
          value: http
        - name: NSS_SDB_USE_CACHE
          value: "no"
        - name: CLUSTER_FORMED_FILE
          value: /usr/share/elasticsearch/data/cluster-formed
      ports:
        - containerPort: 9200
          name: http
          protocol: TCP
        - containerPort: 9300
          name: transport
          protocol: TCP
      readinessProbe:
        exec:
          command:
            - bash
            - -c
            - /mnt/remote-scripts/readiness-probe-script.sh
        failureThreshold: 3
        initialDelaySeconds: 30
        periodSeconds: 5
        successThreshold: 1
        timeoutSeconds: 5
      lifecycle:
        postStart:
          exec:
            command:
            - bash
            - -c
            - |
              /mnt/remote-scripts/post-start-hook.sh > /tmp/post-start-hook.log 2>&1
        preStop:
          exec:
            command:
              - bash
              - -c
              - |
                /mnt/remote-scripts/pre-stop-hook.sh > /tmp/pre-stop-hook.log 2>&1
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        privileged: false
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        runAsUser: 1000
      volumeMounts:
        - mountPath: /usr/share/elasticsearch/bin
          name: local-bin
        - mountPath: /usr/share/elasticsearch/config
          name: local-config
        - mountPath: /usr/share/elasticsearch/plugins
          name: local-plugins
        - mountPath: /usr/share/elasticsearch/data
          name: data
        - mountPath: /usr/share/elasticsearch/logs
          name: log
        - mountPath: /mnt/remote-config
          name: es-cm
          readOnly: true
        - mountPath: /mnt/remote-scripts
          name: scripts
          readOnly: true
        - mountPath: /tmp
          name: tmp-volume
    - name: exporter
      command:
        - /bin/elasticsearch_exporter
        - "--es.uri=http://localhost:9200"
        - "--es.ssl-skip-verify"
      ports:
        - name: metrics
          containerPort: {{.Values.exporter.service.port}}
      env:
        - name: SERVICE_PORT
          value: {{.Values.exporter.service.port | quote }}
      livenessProbe:
        httpGet:
          path: /healthz
          port: metrics
        initialDelaySeconds: 5
        timeoutSeconds: 5
        periodSeconds: 5
      readinessProbe:
        httpGet:
          path: /healthz
          port: metrics
        initialDelaySeconds: 1
        timeoutSeconds: 5
        periodSeconds: 5
    - name: es-agent
      image: {{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.agent.repository }}:{{ .Values.image.agent.tag }}
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      command:
      - /usr/share/elasticsearch/bin/es-agent
      ports:
      - name: agent
        containerPort: 8080
        protocol: TCP
      env:
      - name: POD_IP
        valueFrom:
          fieldRef:
            apiVersion: v1
            fieldPath: status.podIP
      - name: POD_NAME
        valueFrom:
          fieldRef:
            apiVersion: v1
            fieldPath: metadata.name
      - name: KB_NAMESPACE
        valueFrom:
          fieldRef:
            apiVersion: v1
            fieldPath: metadata.namespace
      - name: POD_FQDN
        value: $(POD_NAME).$(ES_COMPONENT_NAME)-headless.$(KB_NAMESPACE).svc.$(CLUSTER_DOMAIN)
      - name: NODE_NAME
        valueFrom:
          fieldRef:
            apiVersion: v1
            fieldPath: spec.nodeName
      - name: ELASTIC_USERNAME
        value: "elastic"
      - name: ELASTIC_PASSWORD
        value: "$(ELASTIC_USER_PASSWORD)"
      - name: ELASTICSEARCH_HOST
        value: "localhost"
      - name: ELASTICSEARCH_PORT
        value: "9200"
      - name: AGENT_PORT
        value: "8080"
      livenessProbe:
        httpGet:
          path: /health
          port: agent
        initialDelaySeconds: 10
        timeoutSeconds: 5
        periodSeconds: 10
      readinessProbe:
        httpGet:
          path: /health
          port: agent
        initialDelaySeconds: 5
        timeoutSeconds: 5
        periodSeconds: 5
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
          - ALL
        privileged: false
        readOnlyRootFilesystem: false
        runAsNonRoot: true
        runAsUser: 1000
      volumeMounts:
      - mountPath: /usr/share/elasticsearch/bin
        name: local-bin
      - mountPath: /usr/share/elasticsearch/config
        name: local-config
      - mountPath: /usr/share/elasticsearch/data
        name: data
  securityContext:
    fsGroup: 1000
  volumes:
    - emptyDir: { }
      name: log
    - emptyDir: { }
      name: tmp-volume
    - emptyDir: { }
      name: local-bin
    - emptyDir: { }
      name: local-config
    - emptyDir: { }
      name: local-plugins
    - emptyDir: { }
      name: plugins
{{- end }}