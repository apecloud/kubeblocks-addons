{{- $clusterName := .CLUSTER_NAME }}
{{- $defaultRoles := .ELASTICSEARCH_ROLES }}
{{- $namespace := .CLUSTER_NAMESPACE }}
{{- $zoneAwareEnabled := .ZONE_AWARE_ENABLED }}

{{- $mode := "multi-node" }}
{{- if index . "mode" }}
{{- $mode = $.mode }}
{{- end }}

{{- $esVersion := "0.1.0" }}
{{- if index . "version" }}
{{- $esVersion = $.version }}
{{- end }}

cluster:
  name: {{ .CLUSTER_NAMESPACE }}
  routing:
    allocation:
      awareness:
        {{- if eq $zoneAwareEnabled "true" }}
        attributes: zone,k8s_node_name
        force:
          zone:
            values: ${ALL_ZONES}
        {{- else }}
        attributes: k8s_node_name
        {{- end }}
# In ES 6.x, discovery configuration is handled differently
discovery:
{{- if eq $mode "multi-node" }}
  zen:
    {{- $masterCount := 0 }}
    {{- $parts := splitList ";" .ALL_CMP_REPLICA_FQDN }}
    {{- range $part := $parts }}
      {{- if hasPrefix "master:" $part }}
        {{- $masterPart := trimPrefix "master:" $part }}
        {{- $masters := splitList "," $masterPart }}
        {{- $masterCount = len $masters }}
      {{- end }}
    {{- end }}
    # Calculate minimum_master_nodes as quorum: (master_count / 2) + 1
    # This ensures cluster stability and prevents data loss
    minimum_master_nodes: {{ add (div $masterCount 2) 1 }}
    ping:
      unicast:
        hosts:
  {{- range $part := $parts }}
    {{- if hasPrefix "master:" $part }}
      {{- $masterPart := trimPrefix "master:" $part }}
      {{- $masters := splitList "," $masterPart }}
     {{- range $master := $masters }}
        - {{ $master }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- else }}
  type: {{ $mode }}
{{- end }}

http:
  cors:
    enabled: true
    allow-origin: "*"
    allow-headers: Authorization,X-Requested-With,Content-Type,Content-Length
  publish_host: ${POD_FQDN}

network:
  host: "0"
  publish_host: ${POD_IP}

node:
  attr:
    k8s_node_name: ${NODE_NAME}
    {{- if eq $zoneAwareEnabled "true" }}
    zone: ${CURRENT_ZONE}
    {{- end }}
  name: ${POD_NAME}
  store:
    allow_mmap: false
{{- if eq $mode "multi-node" }}
# https://www.elastic.co/guide/en/elasticsearch/reference/7.7/modules-node.html
  {{- $roles := $defaultRoles }}
  {{- if index . "roles" }}
  {{- $roles = $.roles }}
  {{- end }}
  {{- $myRoles := $roles | splitList "," }}
  {{- if semverCompare "<7.9" $esVersion }}
  {{- range $i, $e := $myRoles }}
    {{- if ne $e "transform" }}
  {{ $e }}: true
    {{- end }}
  {{- end }}
  {{- else }}
  roles:
  {{- range $i, $e := $myRoles }}
  - {{ $e }}
  {{- end }}
  {{- end }}
{{- end }}

path:
  data: /usr/share/elasticsearch/data
  logs: /usr/share/elasticsearch/logs

xpack:
{{- if eq (index $ "TLS_ENABLED") "true" }}
# The ssl files must be placed in the ES config directory, otherwise, the following error will be reported:
# failed to load SSL configuration [xpack.security.transport.ssl] - cannot read configured PEM certificate_authorities [/etc/pki/tls/ca.crt]
# because access to read the file is blocked; SSL resources should be placed in the [/usr/share/elasticsearch/config] directory
  security:
    enabled: "true"
    authc:
      realms:
        file:
          file1:
            order: 0
        native:
          native1:
            order: 1
            enabled: true
    transport:
      ssl:
        enabled: true
        verification_mode: certificate
        client_authentication: required
        key: /usr/share/elasticsearch/config/key.pem
        certificate: /usr/share/elasticsearch/config/cert.pem
        certificate_authorities: ["/usr/share/elasticsearch/config/ca.pem"]
    http:
      ssl:
        enabled: true
        key: /usr/share/elasticsearch/config/key.pem
        certificate: /usr/share/elasticsearch/config/cert.pem
        certificate_authorities: ["/usr/share/elasticsearch/config/ca.pem"]
    audit:
      enabled: true
{{- else }}
  security:
    enabled: "false"
{{- end }}