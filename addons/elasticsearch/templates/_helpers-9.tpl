{{- define "elasticsearch9.cmpdName" -}}
elasticsearch-9-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearchMaster9.cmpdName" -}}
elasticsearch-master-9-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearchData9.cmpdName" -}}
elasticsearch-data-9-{{ .Chart.Version }}
{{- end -}}

{{- define "elasticsearch9.cmpdRegexPattern" -}}
^elasticsearch-9-
{{- end -}}

{{- define "elasticsearchMaster9.cmpdRegexPattern" -}}
^elasticsearch-master-9-
{{- end -}}

{{- define "elasticsearchData9.cmpdRegexPattern" -}}
^elasticsearch-data-9-
{{- end -}}

{{- define "elasticsearch9.cmpdFamilyRegexPattern" -}}
^elasticsearch(-master|-data)?-9-
{{- end -}}

{{- define "elasticsearch9.configTplName" -}}
elasticsearch-9-config-tpl-{{ .Chart.Version }}
{{- end -}}

{{- define "kibana9.cmpdName" -}}
kibana-9-{{ .Chart.Version }}
{{- end -}}

{{- define "kibana9.cmpdRegexPattern" -}}
^kibana-9-
{{- end -}}

{{- define "kibana9.configTplName" -}}
kibana-9-config-tpl
{{- end -}}

{{- define "elasticsearch9.common" }}
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
        - bash
        - -c
        - |
          set -x
          bash /mnt/remote-scripts/install-plugins.sh
          bash /mnt/remote-scripts/prepare-fs.sh
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
        - bash
        - -c
        - |
          /mnt/remote-scripts/entrypoint.sh
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
      image: {{ .Values.es9.images.elasticsearch | quote }}
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

{{- define "kibana9.common" }}
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
scripts:
  - name: scripts
    template: {{ include "elasticsearch.scriptsTplName" . }}
    namespace: {{ .Release.Namespace }}
    volumeName: scripts
    defaultMode: 0555
vars:
- name: ELASTIC_USER_PASSWORD
  valueFrom:
    credentialVarRef:
      compDef: {{ include "elasticsearch9.cmpdFamilyRegexPattern" . }}
      name: elastic
      optional: false
      password: Required
      multipleClusterObjectOption:
        strategy: individual
- name: KIBANA_SYSTEM_USER_PASSWORD
  valueFrom:
    credentialVarRef:
      compDef: {{ include "elasticsearch9.cmpdFamilyRegexPattern" . }}
      name: kibana_system
      optional: false
      password: Required
      multipleClusterObjectOption:
        strategy: individual
- name: ELASTICSEARCH_HOST
  valueFrom:
    serviceVarRef:
      compDef: {{ include "elasticsearch9.cmpdFamilyRegexPattern" . }}
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
      /mnt/remote-scripts/kibana-entrypoint.sh
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
    - mountPath: /mnt/remote-scripts
      name: scripts
      readOnly: true
    - mountPath: /usr/share/kibana/config
      name: kibana-cm
  securityContext:
    fsGroup: 1000
{{- end }}
