{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $extraEnv := index $.cluster.metadata.annotations "kubeblocks.io/extra-env" | fromJson }}
{{- $masterComponents := $extraEnv.MASTER_COMPONENTS | splitList "," }}
{{- $dataComponents := index $extraEnv "DATA_COMPONENTS" | default "" | splitList "," }}
{{- $ingestComponents := index $extraEnv "INGEST_COMPONENTS" | default "" | splitList "," }}
{{- $transformComponents := index $extraEnv "TRANSFORM_COMPONENTS" | default "" | splitList "," }}
{{- $mlComponents := index $extraEnv "ML_COMPONENTS" | default "" | splitList "," }}
{{- $allComponents := dict "master" $masterComponents "data" $dataComponents "ingest" $ingestComponents "transform" $transformComponents "ml" $mlComponents }}

cluster:
  name: {{ $clusterName }}
  routing:
    allocation:
      awareness:
        attributes: k8s_node_name
  initial_master_nodes:
{{- range $i, $name := $masterComponents }}
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
{{- range $i, $name := $masterComponents }}
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
  {{- $hasRole := false }}
  {{- range $role, $components := $allComponents }}
    {{- range $i, $e := $components }}
      {{- if eq $e $.component.name }}
      {{- $hasRole = true }}
  - {{ $role }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if not $hasRole }}
  {{- range $role, $components := $allComponents }}
  - {{ $role }}
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