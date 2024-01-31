{{- $client_port_info := getPortByName ( index $.podSpec.containers 0 ) "client" }}
{{- $client_port := 2181 }}
{{- if $client_port_info }}
{{- $client_port = $client_port_info.containerPort | int }}
{{- end }}
{{- $quorum_port_info := getPortByName ( index $.podSpec.containers 0 ) "quorum" }}
{{- $quorum_port := 2888 }}
{{- if $quorum_port_info }}
{{- $quorum_port = $quorum_port_info.containerPort | int }}
{{- end }}
{{- $election_port_info := getPortByName ( index $.podSpec.containers 0 ) "election" }}
{{- $election_port := 3888 }}
{{- if $election_port_info }}
{{- $election_port = $election_port_info.containerPort | int }}
{{- end }}

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
dataDir=/bitnami/zookeeper/data
#
dataLogDir=/bitnami/zookeeper/log
# the port at which the clients will connect
clientPort={{- $client_port }}
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
# metricsProvider.className=org.apache.zookeeper.metrics.prometheus.PrometheusMetricsProvider
# metricsProvider.httpPort=7000
# metricsProvider.exportJvmInfo=true

# whitelist
4lw.commands.whitelist=srvr, mntr, ruok, conf

# cluster server list
{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $zk_component := fromJson "{}" }}
{{- range $i, $e := $.cluster.spec.componentSpecs }}
  {{- if eq $e.componentDefRef "zookeeper" }}
    {{- $zk_component = $e }}
  {{- end }}
{{- end }}

{{- printf "\n" }}
{{- $replicas := $zk_component.replicas | int }}
{{- range $i, $e := until $replicas }}
  {{- printf "server.%d=%s-%s-%d.%s-%s-headless.%s.svc.cluster.local:%d:%d:participant;0.0.0.0:%d\n" $i $clusterName $zk_component.name $i $clusterName $zk_component.name $namespace $quorum_port $election_port $client_port }}
{{- end }}