{{- $component_index := $.component.name | splitList "-" | mustLast | atoi }}

{{- $compInfo := get $.dynamicCompInfos $component_index }}
{{- $ob_container := getContainerByName $e.containers "observer-container" }}
{{- $metrics_container := getContainerByName $e.containers "metrics" }}

{{- $ob_port_info := getPortByName $ob_container "sql" }}
{{- $rpc_port_info := getPortByName $ob_container "rpc" }}
{{- $metrics_port_info := getPortByName $e.containers "http" }}
{{- $prof_port_info := getPortByName $e.containers "pprof" }}

## for ob port
{{- $ob_port := 2881 }}
{{- if $ob_port_info }}
  {{- $ob_port = $ob_port_info.containerPort }}
{{- end }}
COMP_MYSQL_PORT = {{ $ob_port }}


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
METRICS_PORT = {{ $metrics_port }}

## for pprof port
{{- $perf_port := 8089 }}
{{- if $prof_port_info }}
  {{- $perf_port = $prof_port_info.containerPort }}
{{- end }}
PPOF_PORT = {{ $perf_port }}
