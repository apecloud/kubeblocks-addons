#!/bin/sh
set -ex
{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- /* find redis-twemproxy component */}}
{{- $proxy_component := fromJson "{}" }}
{{- $redis_component := fromJson "{}" }}
{{- range $i, $e := $.cluster.spec.componentSpecs }}
  {{- if index $e "componentDefRef" }}
    {{- if eq $e.componentDefRef "redis-twemproxy-0.5" }}
      {{- $proxy_component = $e }}
    {{- else if eq $e.componentDefRef "redis-twemproxy" }}
      {{- $proxy_component = $e }}
    {{- else if eq $e.componentDefRef "redis-7" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDefRef "redis-5" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDefRef "redis" }}
      {{- $redis_component = $e }}
    {{- end }}
  {{- end }}
  {{- if index $e "componentDef" }}
    {{- if eq $e.componentDef "redis-twemproxy-0.5" }}
      {{- $proxy_component = $e }}
    {{- else if eq $e.componentDef "redis-twemproxy" }}
      {{- $proxy_component = $e }}
    {{- else if eq $e.componentDef "redis-7" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDef "redis-5" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDef "redis" }}
      {{- $redis_component = $e }}
    {{- end }}
  {{- end }}
{{- end }}
{{- /* build redis-twemproxy config */}}
echo "alpha:" > /etc/proxy/nutcracker.conf
echo "  listen: 0.0.0.0:22121" >> /etc/proxy/nutcracker.conf
echo "  hash: fnv1a_64" >> /etc/proxy/nutcracker.conf
echo "  distribution: ketama" >> /etc/proxy/nutcracker.conf
echo "  auto_eject_hosts: true" >> /etc/proxy/nutcracker.conf
echo "  redis: true" >> /etc/proxy/nutcracker.conf
echo "  server_retry_timeout: 2000" >> /etc/proxy/nutcracker.conf
echo "  server_failure_limit: 1" >> /etc/proxy/nutcracker.conf
echo "  servers:" >> /etc/proxy/nutcracker.conf
echo "    - {{ $clusterName }}-{{ $redis_component.name }}.{{ $namespace }}.svc:6379:1 {{ $clusterName }}" >> /etc/proxy/nutcracker.conf