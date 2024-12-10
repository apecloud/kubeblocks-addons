{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $kafka_zk_from_service_ref := fromJson "{}" }}

{{- if index $.component "serviceReferences" }}
  {{- range $i, $e := $.component.serviceReferences }}
    {{- if eq $i "kafkaZookeeper" }}
      {{- $kafka_zk_from_service_ref = $e }}
      {{- break }}
    {{- end }}
  {{- end }}
{{- end }}

# Try to get zookeeper from service reference first, if zookeeper service reference is empty, get default zookeeper componentDef in ClusterDefinition
{{- $zk_server := "" }}
{{- if $kafka_zk_from_service_ref }}
  {{- if index $kafka_zk_from_service_ref.spec "endpoint" }}
     {{- $zk_server = $kafka_zk_from_service_ref.spec.endpoint.value }}
  {{- else }}
     {{- $zk_server = printf "%s-zookeeper.%s.svc:2181" $clusterName $namespace }}
  {{- end }}
{{- else }}
  {{- $zk_server = printf "%s-zookeeper.%s.svc:2181" $clusterName $namespace }}
{{- end }}
KB_KAFKA_ZOOKEEPER_CONN: {{ $zk_server }}