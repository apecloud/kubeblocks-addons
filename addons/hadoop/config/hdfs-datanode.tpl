<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
    <property>
        <name>dfs.nameservices</name>
        <value>{{- .CLUSTER_NAME }}</value>
    </property>

    <property>
        <name>dfs.datanode.data.dir</name>
        <value>{{- .HDFS_DATANODE_DATA_DIR }}</value>
    </property>

    <property>
        <name>dfs.ha.namenodes.{{- .CLUSTER_NAME }}</name>
        <value>nn0,nn1</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-address.{{- .CLUSTER_NAME }}.nn0</name>
        <value>{{- .CLUSTER_NAME }}-namenode-0.{{- .CLUSTER_NAME }}-namenode-headless.{{-
            .NAMESPACE }}.svc.{{- .CLUSTER_DOMAIN }}:{{- .HDFS_NAMENODE_RPC_PORT }}</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-address.{{- .CLUSTER_NAME }}.nn1</name>
        <value>{{- .CLUSTER_NAME }}-namenode-1.{{- .CLUSTER_NAME }}-namenode-headless.{{-
            .NAMESPACE }}.svc.{{- .CLUSTER_DOMAIN }}:{{- .HDFS_NAMENODE_RPC_PORT }}</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.{{- .CLUSTER_NAME }}.nn0</name>
        <value>{{- .CLUSTER_NAME }}-namenode-0.{{- .CLUSTER_NAME }}-namenode-headless.{{-
            .NAMESPACE }}.svc.{{- .CLUSTER_DOMAIN }}:{{- .HDFS_NAMENODE_HTTP_PORT }}</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.{{- .CLUSTER_NAME }}.nn1</name>
        <value>{{- .CLUSTER_NAME }}-namenode-1.{{- .CLUSTER_NAME }}-namenode-headless.{{-
            .NAMESPACE }}.svc.{{- .CLUSTER_DOMAIN }}:{{- .HDFS_NAMENODE_HTTP_PORT }}</value>
    </property>
    <property>
        <name>dfs.replication</name>
        <value>{{- .HDFS_REPLICATION }}</value>
    </property>
    <property>
        <name>dfs.client.block.write.replace-datanode-on-failure.policy</name>
        <value>{{- .HDFS_CLIENT_REPLACE_DATANODE_ON_FAILURE_POLICY }}</value>
    </property>
</configuration>