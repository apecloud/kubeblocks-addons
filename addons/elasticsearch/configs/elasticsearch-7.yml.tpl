{{- $clusterName := .CLUSTER_NAME }}
{{- $defaultRoles := "master,data" }}
{{- $namespace := .CLUSTER_NAMESPACE }}

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
        attributes: k8s_node_name
{{- if eq $mode "multi-node" }}
  initial_master_nodes:
  {{- $parts := splitList ";" .ALL_CMP_REPLICA_LIST }}
  {{- range $part := $parts }}
    {{- if hasPrefix "master:" $part }}
      {{- $masterPart := trimPrefix "master:" $part }}
      {{- $masters := splitList "," $masterPart }}
     {{- range $master := $masters }}
  - {{ $master }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

discovery:
# the default of discovery.type is multi-node, but can't set it to multi-node explicitly in 7.x version
{{- if eq $mode "single-node" }}
  type: {{ $mode }}
{{- end }}
{{- if eq $mode "multi-node" }}
  seed_hosts:
  {{- $parts := splitList ";" .ALL_CMP_REPLICA_FQDN }}
  {{- range $part := $parts }}
    {{- if hasPrefix "master:" $part }}
      {{- $masterPart := trimPrefix "master:" $part }}
      {{- $masters := splitList "," $masterPart }}
     {{- range $master := $masters }}
  - {{ $master }}
      {{- end }}
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
  {{ $e }}: true
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
  security:
    enabled: "false"
  ml:
    enabled: "false"
