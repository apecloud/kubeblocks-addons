{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $extraEnv := index $.cluster.metadata.annotations "kubeblocks.io/extra-env" | fromJson }}
{{- $master_components := index $extraEnv "MASTER_COMPONENTS" | default "" | splitList "," }}
{{- $data_components := index $extraEnv "DATA_COMPONENTS" | default "" | splitList "," }}
{{- $ingest_components := index $extraEnv "INGEST_COMPONENTS" | default "" | splitList "," }}
{{- $transform_components := index $extraEnv "TRANSFORM_COMPONENTS" | default "" | splitList "," }}

cluster:
  name: {{ $clusterName }}
  routing:
    allocation:
      awareness:
        attributes: k8s_node_name
  initial_master_nodes:
{{- range $i, $name := $master_components }}
{{- range $j, $spec := $.cluster.spec.componentSpecs }}
{{- if eq $spec.name $name }}
{{- $replicas := $spec.replicas | int }}
{{- range $idx, $e := until $replicas }}
  - {{ printf "%s-%s-%d" $clusterName $name $idx }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

discovery:
  type: multi-node
  seed_hosts:
{{- range $i, $name := $master_components }}
{{- range $j, $spec := $.cluster.spec.componentSpecs }}
{{- if eq $spec.name $name }}
{{- $replicas := $spec.replicas | int }}
{{- range $idx, $e := until $replicas }}
  - {{ printf "%s-%s-%d.%s-%s-headless.%s.svc.%s" $clusterName $name $idx $clusterName $name $namespace $.clusterDomain }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

http:
  cors:
    enabled: true
    allow-origin: "*"
    allow-headers: Authorization,X-Requested-With,Content-Type,Content-Length
  publish_host: ${KB_POD_FQDN}

network:
  host: "0"
  publish_host: ${POD_IP}

node:
  attr:
    k8s_node_name: ${NODE_NAME}
  name: ${POD_NAME}
  store:
    allow_mmap: false
  roles:
  {{- range $i, $e := $master_components }}
  {{- if eq $e $.component.name }}
  - master
  {{- end }}
  {{- end }}
  {{- range $i, $e := $data_components }}
  {{- if eq $e $.component.name }}
  - data
  {{- end }}
  {{- end }}
  {{- range $i, $e := $ingest_components }}
  {{- if eq $e $.component.name }}
  - ingest
  {{- end }}
  {{- end }}
  {{- range $i, $e := $transform_components }}
  {{- if eq $e $.component.name }}
  - transform
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