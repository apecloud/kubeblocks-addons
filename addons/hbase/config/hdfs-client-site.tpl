<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

{{- $nodes := splitList "," .HDFS_NAMENODE_NODES }}
{{- $podFQDNsRaw := default .HDFS_NAMENODE_POD_FQDNS_DEFAULT .HDFS_NAMENODE_POD_FQDNS }}
{{- if eq (trim $podFQDNsRaw) "" }}
{{- fail "either serviceRefVarRef.podFQDNs or hdfs.namenodePodFQDNs must be provided" }}
{{- end }}
{{- $podFQDNs := splitList "," $podFQDNsRaw }}
{{- $rpcPort := .HDFS_NAMENODE_RPC_PORT }}
{{- $httpPort := .HDFS_NAMENODE_HTTP_PORT }}
{{- $ns := .HDFS_NAMESERVICE }}
{{- if ne (len $nodes) (len $podFQDNs) }}
{{- fail "HDFS_NAMENODE_NODES and HDFS_NAMENODE_POD_FQDNS must have the same number of entries" }}
{{- end }}

<configuration>
    <property>
        <name>dfs.nameservices</name>
        <value>{{- .HDFS_NAMESERVICE }}</value>
    </property>

    <property>
        <name>dfs.ha.namenodes.{{- .HDFS_NAMESERVICE }}</name>
        <value>{{- .HDFS_NAMENODE_NODES }}</value>
    </property> {{- range $i, $nn := $nodes }} <property>
        <name>dfs.namenode.rpc-address.{{ $ns }}.{{ $nn }}</name>
        <value>{{ trim (index $podFQDNs $i) }}:{{ $rpcPort }}</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.{{ $ns }}.{{ $nn }}</name>
        <value>{{ trim (index $podFQDNs $i) }}:{{ $httpPort }}</value>
    </property> {{- end }} <property>
        <name>dfs.client.failover.proxy.provider.{{- .HDFS_NAMESERVICE }}</name>
        <value>org.apache.hadoop.hdfs.server.namenode.ha.ConfiguredFailoverProxyProvider</value>
    </property>

    <property>
        <name>dfs.replication</name>
        <value>{{- .HDFS_REPLICATION }}</value>
    </property>

    <property>
        <name>dfs.webhdfs.enabled</name>
        <value>{{- .HDFS_WEBHDFS_ENABLED }}</value>
    </property>

    <property>
        <name>dfs.permissions.enabled</name>
        <value>{{- .HDFS_PERMISSIONS_ENABLED }}</value>
    </property>
</configuration>