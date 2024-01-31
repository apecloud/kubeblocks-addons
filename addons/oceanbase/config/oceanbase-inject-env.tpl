{{- $component_index := $.component.name | splitList "-" | mustLast | atoi }}

{{- $compInfo := index $.dynamicCompInfos $component_index }}
{{- $ob_container := getContainerByName $compInfo.containers "observer-container" }}
{{- $metrics_container := getContainerByName $compInfo.containers "metrics" }}

{{- $ob_port_info := getPortByName $ob_container "sql" }}
{{- $rpc_port_info := getPortByName $ob_container "rpc" }}
{{- $metrics_port_info := getPortByName $metrics_container "http" }}
{{- $manager_port_info := getPortByName $metrics_container "pprof" }}
{{- $cm_port_info := getPortByName $metrics_container "config-manager" }}

## for ob port
{{- $ob_port := 2881 }}
{{- if $ob_port_info }}
  {{- $ob_port = $ob_port_info.containerPort }}
{{- end }}
COMP_MYSQL_PORT = {{ $ob_port }}
OB_SERVICE_PORT = {{ $ob_port }}
## for ob rpc port
{{- $rpc_port := 2882 }}
{{- if $rpc_port_info }}
  {{- $rpc_port = $rpc_port_info.containerPort }}
{{- end }}
COMP_RPC_PORT = {{ $rpc_port }}

## for metrics port
{{- $metrics_port := 8088 }}
{{- if $metrics_port_info }}
  {{- $metrics_port = $metrics_port_info.containerPort }}
{{- end }}
SERVICE_PORT = {{ $metrics_port }}

## for manager port
{{- $manager_port := 8089 }}
{{- if $manager_port_info }}
  {{- $manager_port = $manager_port_info.containerPort }}
{{- end }}
MANAGER_PORT = {{ $manager_port }}

## for config-manager port
{{- $cm_port := 9901 }}
{{- if $cm_port_info }}
  {{- $cm_port = $cm_port_info.containerPort }}
{{- end }}
CONF_MANAGER_PORT = {{ $cm_port }}
