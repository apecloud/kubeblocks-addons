<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
    <property>
        <name>dfs.nameservices</name>
        <value>{{- .CLUSTER_NAME }}</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>{{- .HDFS_NAMENODE_NAME_DIR }}</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-address</name>
        <value>0.0.0.0:{{- .HDFS_NAMENODE_RPC_PORT }}</value>
    </property>
    <property>
        <name>dfs.namenode.http-address</name>
        <value>0.0.0.0:{{- .HDFS_NAMENODE_HTTP_PORT }}</value>
    </property>
    <property>
        <name>dfs.permissions.enable</name>
        <value>{{- .HDFS_PERMISSIONS_ENABLED }}</value>
    </property>
    <property>
        <name>dfs.namenode.datanode.registration.ip-hostname-check</name>
        <value>{{- .HDFS_REGISTRATION_IP_HOSTNAME_CHECK }}</value>
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
