{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $solr_zk_from_service_ref := fromJson "{}" }}

{{- if index $.component "serviceReferences" }}
  {{- range $i, $e := $.component.serviceReferences }}
    {{- if eq $i "solrZookeeper" }}
      {{- $solr_zk_from_service_ref = $e }}
      {{- break }}
    {{- end }}
  {{- end }}
{{- end }}

# Try to get zookeeper from service reference first, if zookeeper service reference is empty, get default zookeeper componentDef in ClusterDefinition
{{- $zk_server := "" }}
{{- if $solr_zk_from_service_ref }}
  {{- if and (index $solr_zk_from_service_ref.spec "endpoint")}}
     {{- $zk_server = printf "%s" $solr_zk_from_service_ref.spec.endpoint.value}}
  {{- end }}
{{- end }}

SOLR_ZK_HOSTS: {{ $zk_server }}