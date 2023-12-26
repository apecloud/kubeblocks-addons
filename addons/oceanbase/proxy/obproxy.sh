#!/bin/bash
if [ -z $APP_NAME ]; then
    echo "env variable APP_NAME is required"
    exit 1
fi

if [ -z $PROXYRO_PASSWORD_HASH ]; then
    PROXYRO_PASSWORD_HASH=`echo -n "$PROXYRO_PASSWORD" | sha1sum | awk '{print $1}'`
fi

# http://svc-ob-configserver.$(KB_NAMESPACE).svc:8080/services?Action=GetObProxyConfig
{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $config_server_comp := fromJson "{}" }}
{{- range $i, $c := $.cluster.spec.componentSpecs }}
  {{- if eq "oceanbase-configserver" $c.componentDefRef }}
    {{- $config_server_comp = $c }}
    {{- break }}
  {{- end }}
{{- end }}
{{- if not $config_server_comp }}
echo "no config server component found"
exit 1
{{- end }}
{{- $svc_name := printf "%s-%s-%s.%s.svc.%s" $clusterName $config_server_comp.name "configserver" $namespace $.clusterDomain }}
{{- $svc_port := "8080" }}
CONFIG_URL={{ printf "http://%s:%s/services?Action=GetObProxyConfig" $svc_name $svc_port }}

if [ ! -z $CONFIG_URL ]; then
  echo "use config server"
  cd /home/admin/obproxy &&  /home/admin/obproxy/bin/obproxy -p 2883 -l 2884 -n ${APP_NAME} -o observer_sys_password=${PROXYRO_PASSWORD_HASH},obproxy_config_server_url="${CONFIG_URL}",prometheus_sync_interval=1,enable_metadb_used=false,skip_proxy_sys_private_check=true,log_dir_size_threshold=10G,enable_proxy_scramble=true,enable_strict_kernel_release=false --nodaemon
elif [ ! -z $RS_LIST ]; then
  echo "use rslist"
  cd /home/admin/obproxy && /home/admin/obproxy/bin/obproxy -p 2883 -l 2884 -n ${APP_NAME} -c ${OB_CLUSTER} -r "${RS_LIST}" -o observer_sys_password=${PROXYRO_PASSWORD_HASH},prometheus_sync_interval=1,enable_metadb_used=false,skip_proxy_sys_private_check=true,log_dir_size_threshold=10G,enable_proxy_scramble=true,enable_strict_kernel_release=false --nodaemon
else
  echo "no config server or rs list"
  exit 1
fi
