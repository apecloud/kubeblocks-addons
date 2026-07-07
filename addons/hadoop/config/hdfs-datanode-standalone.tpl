<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>{{- .HDFS_DATANODE_DATA_DIR }}</value>
    </property>

    <property>
        <name>dfs.datanode.data.dir.perm</name>
        <value>700</value>
    </property>

    <property>
        <name>dfs.datanode.failed.volumes.tolerated</name>
        <value>0</value>
    </property>

    <property>
        <name>dfs.datanode.max.transfer.threads</name>
        <value>{{- .HDFS_DATANODE_HANDLER_COUNT }}</value>
    </property>

    <property>
        <name>dfs.datanode.handler.count</name>
        <value>{{- .HDFS_DATANODE_HANDLER_COUNT }}</value>
    </property>

    <property>
        <name>dfs.datanode.address</name>
        <value>0.0.0.0:{{- .HDFS_DATANODE_DATA_PORT }}</value>
    </property>

    <property>
        <name>dfs.datanode.http.address</name>
        <value>0.0.0.0:{{- .HDFS_DATANODE_HTTP_PORT }}</value>
    </property>

    <property>
        <name>dfs.datanode.ipc.address</name>
        <value>0.0.0.0:{{- .HDFS_DATANODE_IPC_PORT }}</value>
    </property>

    <property>
        <name>dfs.datanode.du.reserved</name>
        <value>1073741824</value>
    </property>

    <property>
        <name>dfs.datanode.use.datanode.hostname</name>
        <value>false</value>
    </property>

    <property>
        <name>dfs.namenode.rpc-address</name>
        <value>{{- .CLUSTER_NAME }}-namenode-0.{{- .CLUSTER_NAME }}-namenode-headless.{{-
            .NAMESPACE }}.svc.{{- .CLUSTER_DOMAIN }}:{{- .HDFS_NAMENODE_RPC_PORT }}</value>
    </property>
    <property>
        <name>dfs.namenode.http-address</name>
        <value>{{- .CLUSTER_NAME }}-namenode-0.{{- .CLUSTER_NAME }}-namenode-headless.{{-
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

    <property>
        <name>dfs.permissions.enabled</name>
        <value>{{- .HDFS_PERMISSIONS_ENABLED }}</value>
    </property>

    <property>
        <name>dfs.hosts</name>
        <value>{{- .HDFS_CONF_DIR }}/dfs.include</value>
    </property>

    <property>
        <name>dfs.hosts.exclude</name>
        <value>{{- .HDFS_CONF_DIR }}/dfs.exclude</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.enabled</name>
        <value>true</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.spec</name>
        <value>1000,1</value>
    </property>
</configuration>