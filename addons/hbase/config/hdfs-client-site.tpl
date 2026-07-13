<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
    <property>
        <name>dfs.nameservices</name>
        <value>{{- .HDFS_NAMESERVICE }}</value>
    </property>

    <property>
        <name>dfs.ha.namenodes.{{- .HDFS_NAMESERVICE }}</name>
        <value>{{- .HDFS_NAMENODE_NODES }}</value>
    </property>

{{- $nodes := splitList "," .HDFS_NAMENODE_NODES }}
{{- $rpcEndpoints := splitList "," .HDFS_NAMENODE_RPC_ENDPOINTS }}
{{- $hosts := splitList "," .HDFS_NAMENODE_HOSTS }}
{{- $httpPort := .HDFS_NAMENODE_HTTP_PORT }}
{{- $ns := .HDFS_NAMESERVICE }}
{{- if ne (len $nodes) (len $rpcEndpoints) }}
{{- fail "HDFS_NAMENODE_NODES and HDFS_NAMENODE_RPC_ENDPOINTS must have the same number of entries" }}
{{- end }}
{{- if ne (len $nodes) (len $hosts) }}
{{- fail "HDFS_NAMENODE_NODES and HDFS_NAMENODE_HOSTS must have the same number of entries" }}
{{- end }}
{{- range $i, $nn := $nodes }}
    <property>
        <name>dfs.namenode.rpc-address.{{ $ns }}.{{ $nn }}</name>
        <value>{{ trim (index $rpcEndpoints $i) }}</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.{{ $ns }}.{{ $nn }}</name>
        <value>{{ trim (index $hosts $i) }}:{{ $httpPort }}</value>
    </property>
{{- end }}

    <property>
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
