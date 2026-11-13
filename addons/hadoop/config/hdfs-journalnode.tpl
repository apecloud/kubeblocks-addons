<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
    <property>
        <name>dfs.nameservices</name>
        <value>{{- .CLUSTER_NAME }}</value>
    </property>

    <property>
        <name>dfs.journalnode.edits.dir</name>
        <value>{{- .HDFS_JOURNALNODE_EDITS_DIR }}</value>
    </property>

    <property>
        <name>dfs.journalnode.rpc-address</name>
        <value>0.0.0.0:{{- .HDFS_JOURNALNODE_RPC_PORT }}</value>
    </property>

    <property>
        <name>dfs.journalnode.http-address</name>
        <value>0.0.0.0:{{- .HDFS_JOURNALNODE_HTTP_PORT }}</value>
    </property>

    <property>
        <name>dfs.journalnode.bind-host</name>
        <value>0.0.0.0</value>
    </property>

    <property>
        <name>dfs.permissions.enabled</name>
        <value>{{- .HDFS_PERMISSIONS_ENABLED }}</value>
    </property>

    <property>
        <name>dfs.replication</name>
        <value>{{- .HDFS_REPLICATION }}</value>
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
        <name>dfs.journalnode.enable.sync</name>
        <value>{{- .HDFS_JOURNALNODE_ENABLE_SYNC }}</value>
    </property>

    <property>
        <name>dfs.journalnode.edit-cache-size.bytes</name>
        <value>{{- .HDFS_JOURNALNODE_EDIT_CACHE_SIZE_BYTES }}</value>
    </property>

    <property>
        <name>dfs.journalnode.sync.interval</name>
        <value>{{- .HDFS_JOURNALNODE_SYNC_INTERVAL_MS }}</value>
    </property>
</configuration>
