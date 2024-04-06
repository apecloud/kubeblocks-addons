{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $master_component := fromJson "{}" }}
{{- range $i, $e := $.cluster.spec.componentSpecs }}
  {{- if eq $e.componentDef "es-master" }}
  {{- $master_component = $e }}
  {{- end }}
{{- end }}
{{- $master_replicas := $master_component.replicas | int }}

cluster:
  name: {{ $clusterName }}
  routing:
    allocation:
      awareness:
        attributes: k8s_node_name
  initial_master_nodes:
{{- range $i, $e := until $master_replicas }}
  - {{ printf "%s-%s-%d" $clusterName $master_component.name $i }}
{{- end }}

discovery:
  type: multi-node
  seed_hosts:
{{- range $i, $e := until $master_replicas }}
  - {{ printf "%s-%s-%d.%s-%s-headless.%s.svc.%s" $clusterName $master_component.name $i $clusterName $master_component.name $namespace $.clusterDomain }}
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
  roles: ${ELASTICSEARCH_ROLES}


path:
  data: /usr/share/elasticsearch/data
  logs: /usr/share/elasticsearch/logs

xpack:
  security:
    enabled: "false"
  ml:
    enabled: "false"