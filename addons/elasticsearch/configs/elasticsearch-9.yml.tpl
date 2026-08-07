{{- $clusterName := .CLUSTER_NAME }}
{{- $defaultRoles := .ELASTICSEARCH_ROLES }}
{{- $namespace := .CLUSTER_NAMESPACE }}
{{- $zoneAwareEnabled := index . "ZONE_AWARE_ENABLED" }}
{{- $currentCompShortName := index . "ES_COMPONENT_SHORT_NAME" }}

{{- /* Determine if current component is master-eligible */}}
{{- $isMasterEligible := false }}
{{- range $r := splitList "," $defaultRoles }}
  {{- if eq (trim $r) "master" }}{{- $isMasterEligible = true }}{{- end }}
{{- end }}

{{- /* Parse ALL_CMP_REPLICA_LIST.
     Formats:
     - Single component (no comp prefix): "pod1" or "pod1,pod2"
     - Multi-component (Flatten): "comp1:pod1,pod2;comp2:pod3,pod4"  */}}
{{- $allPods := list }}
{{- $currentCompPods := list }}
{{- range $segment := splitList ";" .ALL_CMP_REPLICA_LIST }}
  {{- if $segment }}
    {{- $kv := splitList ":" $segment }}
    {{- if gt (len $kv) 1 }}
      {{- $compName := index $kv 0 }}
      {{- $podsPart := index $kv 1 }}
      {{- range $p := splitList "," $podsPart }}
        {{- if $p }}
          {{- $allPods = append $allPods $p }}
          {{- if eq $compName $currentCompShortName }}
            {{- $currentCompPods = append $currentCompPods $p }}
          {{- end }}
        {{- end }}
      {{- end }}
    {{- else }}
      {{- /* Single component: no key prefix */}}
      {{- range $p := splitList "," (index $kv 0) }}
        {{- if $p }}
          {{- $allPods = append $allPods $p }}
          {{- $currentCompPods = append $currentCompPods $p }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{- $mode := "multi-node" }}
{{- if index . "mode" }}
  {{- $mode = $.mode }}
{{- else }}
  {{- if eq (len $allPods) 1 }}
    {{- $mode = "single-node" }}
  {{- end }}
{{- end }}

cluster:
  name: {{ $clusterName }}
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
# INITIAL_MASTER_NODES_BLOCK_START
{{- if and (eq $mode "multi-node") $isMasterEligible $currentCompPods }}
  initial_master_nodes:
    {{- range $master := $currentCompPods }}
  - {{ $master }}
    {{- end }}
{{- end }}
# INITIAL_MASTER_NODES_BLOCK_END

{{- $seedHosts := list }}
{{- if eq $mode "multi-node" }}
  {{- /* Parse ALL_CMP_REPLICA_FQDN, same format as ALL_CMP_REPLICA_LIST */}}
  {{- range $segment := splitList ";" .ALL_CMP_REPLICA_FQDN }}
    {{- if $segment }}
      {{- $kv := splitList ":" $segment }}
      {{- $fqdnsPart := "" }}
      {{- if gt (len $kv) 1 }}
        {{- $fqdnsPart = index $kv 1 }}
      {{- else }}
        {{- $fqdnsPart = index $kv 0 }}
      {{- end }}
      {{- range $f := splitList "," $fqdnsPart }}
        {{- if $f }}{{- $seedHosts = append $seedHosts $f }}{{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{- if or (eq $mode "single-node") $seedHosts }}
discovery:
  {{- if eq $mode "single-node" }}
  type: single-node
  {{- else }}
  seed_hosts:
    {{- range $host := $seedHosts }}
  - {{ $host }}
    {{- end }}
  {{- end }}
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
# https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html#node-roles
  roles:
  {{- $roles := $defaultRoles }}
  {{- if index . "roles" }}
  {{- $roles = $.roles }}
  {{- end }}
  {{- $myRoles := $roles | splitList "," }}
  {{- range $i, $e := $myRoles }}
  - {{ $e }}
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
    enabled: false
    enrollment:
      enabled: false
    transport:
      ssl:
        enabled: false
    http:
      ssl:
        enabled: false
{{- end }}
