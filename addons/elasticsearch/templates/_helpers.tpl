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
{{ include "kblib.helm.resourcePolicy" . }}
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

{{- define "elasticsearchMaster.cmpdRegexPattern" -}}
^elasticsearch-master-
{{- end -}}

{{- define "elasticsearchData.cmpdRegexPattern" -}}
^elasticsearch-data-
{{- end -}}

{{- define "elasticsearch6.cmpdName" -}}
elasticsearch-6-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearchMaster6.cmpdName" -}}
elasticsearch-master-6-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearchData6.cmpdName" -}}
elasticsearch-data-6-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearch6.cmpdRegexPattern" -}}
^elasticsearch-6-
{{- end -}}

{{- define "elasticsearchMaster6.cmpdRegexPattern" -}}
^elasticsearch-master-6-
{{- end -}}

{{- define "elasticsearchData6.cmpdRegexPattern" -}}
^elasticsearch-data-6-
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

{{- define "elasticsearch6.configTplName" -}}
elasticsearch-6-config-tpl-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearch7.configTplName" -}}
elasticsearch-7-config-tpl-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearch8.configTplName" -}}
elasticsearch-8-config-tpl-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearch7.pcrName" -}}
elasticsearch7-pcr
{{- end }}

{{- define "elasticsearch8.pcrName" -}}
elasticsearch8-pcr
{{- end }}

{{- define "kibana6.cmpdName" -}}
kibana-6-{{ .Chart.Version }}
{{- end -}}

{{- define "kibana6.cmpdRegexPattern" -}}
^kibana-6-
{{- end -}}

{{- define "kibana7.cmpdName" -}}
kibana-7-{{ .Chart.Version }}
{{- end -}}

{{- define "kibana7.cmpdRegexPattern" -}}
^kibana-7-
{{- end -}}

{{- define "kibana8.cmpdName" -}}
kibana-8-{{ .Chart.Version }}
{{- end -}}

{{- define "kibana8.cmpdRegexPattern" -}}
^kibana-8-
{{- end -}}

{{- define "kibana6.configTplName" -}}
kibana-6-config-tpl
{{- end -}}

{{- define "kibana7.configTplName" -}}
kibana-7-config-tpl
{{- end -}}

{{- define "kibana8.configTplName" -}}
kibana-8-config-tpl
{{- end -}}

{{- define "kibana.probe" -}}
exec:
  command:
  - bash
  - -c
  - |
    #!/usr/bin/env bash -e

    # Disable nss cache to avoid filling dentry cache when calling curl
    # This is required with Kibana Docker using nss < 3.52
    export NSS_SDB_USE_CACHE=no

    http () {
        local path="${1}"
        set -- -XGET -s --fail -L

        if [ -n "${ELASTICSEARCH_USERNAME}" ] && [ -n "${ELASTICSEARCH_PASSWORD}" ]; then
          set -- "$@" -u "${ELASTICSEARCH_USERNAME}:${ELASTICSEARCH_PASSWORD}"
        fi

        if [ "${TLS_ENABLED}" == "true" ]; then
          READINESS_PROBE_PROTOCOL=https
        else
          READINESS_PROBE_PROTOCOL=http
        fi
        endpoint="${READINESS_PROBE_PROTOCOL}://${POD_IP}:5601"
        STATUS=$(curl --output /dev/null --write-out "%{http_code}" -k "$@" "${endpoint}${path}")
        if [[ "${STATUS}" -eq 200 ]]; then
          exit 0
        fi

        echo "Error: Got HTTP code ${STATUS} but expected a 200"
        exit 1
    }

    http "/app/kibana"
{{- end -}}

{{- define "elasticsearch.common" }}
provider: kubeblocks
description: Elasticsearch is a distributed, restful search engine optimized for speed and relevance on production-scale workloads.
serviceKind: elasticsearch
updateStrategy: Parallel
podManagementPolicy: Parallel
podUpgradePolicy: ReCreate
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
          {{- .Files.Get "scripts/entrypoint.sh" | nindent 10 }}
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
{{- if .Values.zoneAware.enabled }}
        - mountPath: /mnt/zone-aware-mapping
          name: zone-aware-mapping
          readOnly: true
{{- end }}
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
{{- if .Values.zoneAware.enabled }}
    - name: zone-aware-mapping
      configMap:
        name: {{ .Values.zoneAware.configMap }}
{{- end }}
{{- end }}

{{- define "kibana.common" }}
provider: kubeblocks
description: Kibana is a browser-based analytics and search dashboard for Elasticsearch.
serviceKind: kibana
updateStrategy: Parallel
services:
- name: http
  serviceName: http
  spec:
    ipFamilyPolicy: PreferDualStack
    ipFamilies:
    - IPv4
    ports:
    - name: http
      port: 5601
      targetPort: http
tls:
  volumeName: tls
  mountPath: /etc/pki/tls
  caFile: ca.pem
  certFile: cert.pem
  keyFile: key.pem
vars:
- name: ELASTIC_USER_PASSWORD
  valueFrom:
    credentialVarRef:
      compDef: {{ include "elasticsearch.cmpdRegexPattern" . }}
      name: elastic
      optional: false
      password: Required
      multipleClusterObjectOption:
        strategy: individual
- name: KIBANA_SYSTEM_USER_PASSWORD
  valueFrom:
    credentialVarRef:
      compDef: {{ include "elasticsearch.cmpdRegexPattern" . }}
      name: kibana_system
      optional: false
      password: Required
      multipleClusterObjectOption:
        strategy: individual
- name: ELASTICSEARCH_HOST
  valueFrom:
    serviceVarRef:
      compDef: {{ include "elasticsearch.cmpdRegexPattern" . }}
      name: http
      host: Required
      multipleClusterObjectOption:
        strategy: individual
- name: CLUSTER_NAMESPACE
  valueFrom:
    clusterVarRef:
      namespace: Required
- name: TLS_ENABLED
  valueFrom:
    tlsVarRef:
      enabled: Optional
runtime:
  containers:
  - env:
    - name: NSS_SDB_USE_CACHE
      value: "no"
    - name: CLUSTER_DOMAIN
      value: {{ .Values.clusterDomain | quote }}
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    command:
    - bash
    - -c
    - |
      function info() {
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
      }
      if [ "${TLS_ENABLED}" == "true" ]; then
        READINESS_PROBE_PROTOCOL=https
      else
        READINESS_PROBE_PROTOCOL=http
      fi
      # All the components' password of elastic must be the same, So we find the first environment variable that starts with ELASTIC_USER_PASSWORD
      ELASTIC_AUTH_PASSWORD=""
      if [ "${TLS_ENABLED}" == "true" ]; then
        last_value=""
        set +x
        for env_var in $(env | grep -E '^ELASTIC_USER_PASSWORD'); do
          value="${env_var#*=}"
          if [ -n "$value" ]; then
            if [ -n "$last_value" ] && [ "$last_value" != "$value" ]; then
              echo "Error conflicting env $env_var of elastic password values found, all the components' password of elastic must be the same."
              exit 1
            fi
            last_value="$value"
          fi
        done
        ELASTIC_AUTH_PASSWORD="$last_value"
      fi
      for env_var in $(env | grep -E '^ELASTICSEARCH_HOST'); do
        value="${env_var#*=}"
        if [ -n "$value" ]; then
          ELASTICSEARCH_HOST="$value"
          break
        fi
      done
      if [ -z "$ELASTICSEARCH_HOST" ]; then
        echo "Invalid ELASTICSEARCH_HOST"
        exit 1
      fi
      endpoint="${READINESS_PROBE_PROTOCOL}://${ELASTICSEARCH_HOST}.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}:9200"
      common_options="-s -u elastic:${ELASTIC_AUTH_PASSWORD} --fail --connect-timeout 3 -k"
      while true; do
        if [ "${TLS_ENABLED}" == "true" ]; then
          out=$(curl ${common_options} -X GET "${endpoint}/kubeblocks_ca_crt/_doc/1?pretty")
          if [ $? == 0 ]; then
            echo "$out" | grep '"ca.crt" :' | awk -F: '{print $2}' | tr -d '",' | xargs | base64 -d > /tmp/elastic.ca.crt
            info "elasticsearch is ready"
            break
          fi
        else
          curl ${common_options} -X GET "${endpoint}"
          if [ $? == 0 ]; then
            info "elasticsearch is ready"
            break
          fi
        fi
        info "waiting for elasticsearch to be ready"
        sleep 1
      done
      if [ -f /bin/tini ]; then
        /bin/tini -- /usr/local/bin/kibana-docker -e ${endpoint} -H ${POD_IP}
      else
        /usr/local/bin/kibana-docker -e ${endpoint} -H ${POD_IP}
      fi
    name: kibana
    ports:
    - containerPort: 5601
      name: http
      protocol: TCP
    startupProbe:
      failureThreshold: 5
      initialDelaySeconds: 90
      periodSeconds: 10
      successThreshold: 1
      timeoutSeconds: 5
    {{ include "kibana.probe" . | nindent 6 }}
    readinessProbe:
      failureThreshold: 3
      periodSeconds: 10
      successThreshold: 1
      timeoutSeconds: 5
    {{ include "kibana.probe" . | nindent 6 }}
    livenessProbe:
      failureThreshold: 3
      periodSeconds: 10
      successThreshold: 1
      timeoutSeconds: 5
    {{ include "kibana.probe" . | nindent 6 }}
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      privileged: false
      runAsNonRoot: true
      runAsUser: 1000
    volumeMounts:
    - mountPath: /usr/share/kibana/config
      name: kibana-cm
  securityContext:
    fsGroup: 1000
{{- end }}