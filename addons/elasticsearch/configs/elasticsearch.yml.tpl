{{- $clusterName := $.cluster.metadata.name }}
{{- $defaultRoles := "master,data" }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $extraEnv := index $.cluster.metadata.annotations "kubeblocks.io/extra-env" | default "{}" | fromJson }}
{{- $mode := index $extraEnv "mode" | default "multi-node" }}

{{- $allRoles := fromJson "{}" }}
{{- range $i, $spec := $.cluster.spec.componentSpecs }}
    {{- $envName := printf "%s-roles" $spec.name }}
    {{- $roles := index $extraEnv $envName | default $defaultRoles | splitList "," }}
    {{- range $j, $role := $roles }}
        {{- $comps := index $allRoles $role }}
        {{- if not $comps }}
            {{- $comps = list }}
        {{- end }}
        {{- $allRoles = set $allRoles $role (append $comps $spec.name) }}
    {{- end }}
{{- end }}
{{- $masterComponents := $allRoles.master }}

cluster:
  name: {{ $clusterName }}
  routing:
    allocation:
      awareness:
        attributes: k8s_node_name
{{- if eq $mode "multi-node" }}
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
{{- end }}

discovery:
# the default of discovery.type is multi-node, but can't set it to multi-node explicitly in 7.x version
{{- if eq $mode "single-node" }}
  type: {{ $mode }}
{{- end }}
{{- if eq $mode "multi-node" }}
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
{{- if eq $mode "multi-node" }}
  roles:
  {{- $myRoles := index $extraEnv (printf "%s-roles" $.component.name) | default $defaultRoles | splitList "," }}
  {{- range $i, $e := $myRoles }}
  - {{ $e }}
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