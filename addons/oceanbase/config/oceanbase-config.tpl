{{- $phy_memory := getContainerMemory ( index $.podSpec.containers 0 ) }}
{{- $phy_cpu := getContainerCPU ( index $.podSpec.containers 0 ) }}
cpu_count={{$phy_cpu}}
{{- $phy_memory_gb := div $phy_memory 1073741824 | int }}
memory_limit={{- printf "%dG" $phy_memory_gb }}
system_memory=1G
__min_full_resource_pool_memory=1073741824
{{- $data_disk_size := getComponentPVCSizeByName $.component "data-file" }}
{{- $log_disk_size := getComponentPVCSizeByName $.component "data-log" }}
{{- $data_disk_size_gb := div $data_disk_size 1073741824 | int }}
{{- $log_disk_size_gb := div $log_disk_size 1073741824 | int }}
{{- $data_disk_size_gb := round ( mulf $data_disk_size_gb 0.85 ) 0 | int }}
{{- $log_disk_size_gb := round ( mulf $log_disk_size_gb 0.85 ) 0 | int }}
datafile_size={{- printf "%dG" $data_disk_size_gb }}
log_disk_size={{- printf "%dG" $log_disk_size_gb }}
net_thread_count=2
stack_size=512K
cache_wash_threshold=1G
schema_history_expire_time=1d
enable_separate_sys_clog=false
enable_merge_by_turn=false
enable_syslog_recycle=true
enable_syslog_wf=false
max_syslog_file_count=4
{{- $mysql_port_info := getPortByName ( index $.podSpec.containers 0 ) "sql" }}
{{- $mysql_port := 2881 }}
{{- if $mysql_port_info }}
{{- $mysql_port = $mysql_port_info.containerPort }}
{{- end }}
mysql_port={{ $mysql_port }}
{{- $rpc_port_info := getPortByName ( index $.podSpec.containers 0 ) "rpc" }}
{{- $rpc_port := 2882 }}
{{- if $rpc_port_info }}
{{- $rpc_port = $rpc_port_info.containerPort }}
{{- end }}
rpc_port={{ $rpc_port }}
{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $componentName := printf "%s-%s" $clusterName $.component.name}}
{{- $config_server_comp := fromJson "{}" }}
{{- range $i, $c := $.cluster.spec.componentSpecs }}
  {{- if eq "oceanbase-configserver" $c.componentDefRef }}
    {{- $config_server_comp = $c }}
    {{- break }}
  {{- end }}
{{- end }}
{{- if $config_server_comp }}
  {{- $svc_name := printf "%s-%s-%s.%s.svc.%s" $clusterName $config_server_comp.name "configserver" $namespace $.clusterDomain }}
  {{- $svc_port := "8080" }}
obconfig_url={{ printf "http://%s:%s/services?Action=ObRootServiceInfo&ObCluster=%s" $svc_name $svc_port $componentName}}
{{- end }}