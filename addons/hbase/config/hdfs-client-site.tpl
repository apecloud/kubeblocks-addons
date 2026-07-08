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
{{- $rpcPort := .HDFS_NAMENODE_RPC_PORT }}
{{- $httpPort := .HDFS_NAMENODE_HTTP_PORT }}
{{- $ns := .HDFS_NAMESERVICE }}
{{- $clusterDomain := .CLUSTER_DOMAIN }}
{{- $namespace := .NAMESPACE }}
{{- $headlessSvc := printf "%s-namenode-headless" $ns }}
{{- range $nn := $nodes }}
{{- $ordinal := trimPrefix "nn" $nn }}
    <property>
        <name>dfs.namenode.rpc-address.{{ $ns }}.{{ $nn }}</name>
        <value>{{ $ns }}-namenode-{{ $ordinal }}.{{ $headlessSvc }}.{{ $namespace }}.svc.{{ $clusterDomain }}:{{ $rpcPort }}</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.{{ $ns }}.{{ $nn }}</name>
        <value>{{ $ns }}-namenode-{{ $ordinal }}.{{ $headlessSvc }}.{{ $namespace }}.svc.{{ $clusterDomain }}:{{ $httpPort }}</value>
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
