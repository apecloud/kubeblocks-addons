# The number of milliseconds of each tick
tickTime=2000
# Minimum and maximum session timeouts in milliseconds that the server will allow the client to negotiate.
# Defaults to 2 * tickTime and 20 * tickTime respectively.
minSessionTimeout=4000
maxSessionTimeout=40000
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
autopurge.snapRetainCount=5
# Purge task interval in hours
# Set to "0" to disable auto purge feature
autopurge.purgeInterval=12

## Metrics Providers
#
# https://prometheus.io Metrics Exporter
{{ if .ZOOKEEPER_METRICS_MONITOR }}
  {{- printf "metricsProvider.className=org.apache.zookeeper.metrics.prometheus.PrometheusMetricsProvider\n" }}
  {{- printf "metricsProvider.httpPort=%s\n" .ZOOKEEPER_METRICS_PORT}}
  {{- printf "metricsProvider.exportJvmInfo=true\n" }}
{{- end }}

# whitelist
4lw.commands.whitelist=srvr, mntr, ruok, conf, stat, sync

{{- if hasKey $.cluster.metadata.annotations "kubeblocks.io/extra-env" -}}
{{- $extraEnv := index $.cluster.metadata.annotations "kubeblocks.io/extra-env" | fromJson -}}
{{- if hasKey $extraEnv "ZOOKEEPER_STANDALONE_ENABLED" }}
standaloneEnabled={{ $extraEnv.ZOOKEEPER_STANDALONE_ENABLED }}
{{- else }}
standaloneEnabled=false
{{- end -}}
{{- else }}
standaloneEnabled=false
{{- end }}

# dynamic config
reconfigEnabled=true
dynamicConfigFile={{ .ZOOKEEPER_DYNAMIC_CONFIG_FILE }}

# logging
audit.enable=true