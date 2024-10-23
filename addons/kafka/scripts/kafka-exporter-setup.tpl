#!/bin/bash
{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- /* find kafka-server component */}}
{{- $component := fromJson "{}" }}
{{- range $i, $e := $.cluster.spec.componentSpecs }}
  {{- if contains "kafka-combine" $e.componentDef }}
  {{- $component = $e }}
  {{- end }}
{{- end }}
{{- if not $component  }}
{{- /* find kafka-broker component */}}
  {{- range $i, $e := $.cluster.spec.componentSpecs }}
    {{- if contains "kafka-broker" $e.componentDef }}
    {{- $component = $e }}
    {{- end }}
  {{- end }}
{{- end }}
{{- /* build --kafka.server= string */}}
{{- $replicas := $component.replicas | int }}
{{- $servers := "" }}
{{- range $i, $e := until $replicas }}
  {{- $podFQDN := printf "%s-%s-%d.%s-%s-headless.%s.svc.%s" $clusterName $component.name $i $clusterName $component.name $namespace $.clusterDomain }}
  {{- $server := printf "--kafka.server=%s:9094 \\\n" $podFQDN }}
  {{- $servers = printf "%s\t%s" $servers $server }}
{{- end }}
{{ $servers = trimSuffix " \\\n" $servers}}
exec kafka_exporter --web.listen-address=:9308 \
{{- if $.component.tlsConfig }}
  --tls.enabled \
{{- end }}
{{ $servers }}

