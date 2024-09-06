# The number of milliseconds of each tick
tickTime=2000
# The number of ticks that the initial
# synchronization phase can take
initLimit=10
# The number of ticks that can pass between
# sending a request and getting an acknowledgement
syncLimit=30
# the directory where the snapshot is stored.
# do not use /tmp for storage, /tmp here is just
# example sakes.
dataDir={{ .ZOOKEEPER_DATA_DIR }}
#
dataLogDir={{ .ZOOKEEPER_DATA_LOG_DIR }}
# the port at which the clients will connect
clientPort=2181
# the maximum number of client connections.
# increase this if you need to handle more clients
maxClientCnxns=500
#
# Be sure to read the maintenance section of the
# administrator guide before turning on autopurge.
#
# http://zookeeper.apache.org/doc/current/zookeeperAdmin.html#sc_maintenance
#
# The number of snapshots to retain in dataDir
#autopurge.snapRetainCount=3
# Purge task interval in hours
# Set to "0" to disable auto purge feature
#autopurge.purgeInterval=1

## Metrics Providers
#
# https://prometheus.io Metrics Exporter
{{ if .ZOOKEEPER_METRICS_MONITOR }}
  {{- printf "metricsProvider.className=org.apache.zookeeper.metrics.prometheus.PrometheusMetricsProvider\n" }}
  {{- printf "metricsProvider.httpPort=%s\n" .ZOOKEEPER_METRICS_PORT}}
  {{- printf "metricsProvider.exportJvmInfo=true\n" }}
{{- end }}

# whitelist
4lw.commands.whitelist=srvr, mntr, ruok, conf

# cluster server list
{{- printf "\n" }}
{{- $fqnds := splitList "," .ZOOKEEPER_POD_FQDN_LIST }}
{{- range $i, $fqdn := $fqnds }}
  {{- $name := index (splitList "." $fqdn) 0 }}
  {{- $tokens := splitList "-" $name }}
  {{- $ordinal := index $tokens (sub (len $tokens) 1) }}
  {{- if ge $i 3 }}
    {{- printf "server.%s=%s:2888:3888:observer\n" $ordinal $fqdn }}
  {{- else }}
    {{- printf "server.%s=%s:2888:3888:participant\n" $ordinal $fqdn }}
  {{- end }}
{{- end }}



# logging
audit.enable=true