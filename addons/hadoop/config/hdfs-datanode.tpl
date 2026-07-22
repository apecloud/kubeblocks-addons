<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

{{- $name_node_ids := splitList "," .HDFS_HA_NAMENODE_IDS }}
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
        <name>dfs.datanode.data.dir.perm</name>
        <value>700</value>
    </property>

    <property>
        <name>dfs.datanode.failed.volumes.tolerated</name>
        <value>{{- .HDFS_DATANODE_FAILED_VOLUMES_TOLERATED }}</value>
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
        <value>{{- .HDFS_DATANODE_DU_RESERVED }}</value>
    </property>

    <property>
        <name>dfs.datanode.use.datanode.hostname</name>
        <value>false</value>
    </property>

    <property>
        <name>dfs.ha.namenodes.{{- .CLUSTER_NAME }}</name>
        <value>{{ join "," $name_node_ids }}</value>
    </property> {{- range $nn_ordinal, $nn_id :=
    $name_node_ids }} <property>
        <name>dfs.namenode.rpc-address.{{- $.CLUSTER_NAME }}.{{ $nn_id }}</name>
        <value>{{- $.CLUSTER_NAME }}-namenode-{{ $nn_ordinal }}.{{- $.CLUSTER_NAME
    }}-namenode-headless.{{-
            $.NAMESPACE }}.svc.{{- $.CLUSTER_DOMAIN }}:{{- $.HDFS_NAMENODE_RPC_PORT }}</value>
    </property>
    {{- end }} {{- range $nn_ordinal, $nn_id := $name_node_ids }} <property>
        <name>dfs.namenode.http-address.{{- $.CLUSTER_NAME }}.{{ $nn_id }}</name>
        <value>{{- $.CLUSTER_NAME }}-namenode-{{ $nn_ordinal }}.{{- $.CLUSTER_NAME
    }}-namenode-headless.{{-
            $.NAMESPACE }}.svc.{{- $.CLUSTER_DOMAIN }}:{{- $.HDFS_NAMENODE_HTTP_PORT }}</value>
    </property>
    {{- end }} <property>
        <name>dfs.client.failover.proxy.provider.{{- .CLUSTER_NAME }}</name>
        <value>org.apache.hadoop.hdfs.server.namenode.ha.ConfiguredFailoverProxyProvider</value>
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
        <value>{{- .HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE }}</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.enabled</name>
        <value>{{- .HDFS_CLIENT_RETRY_POLICY_ENABLED }}</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.spec</name>
        <value>{{- .HDFS_CLIENT_RETRY_POLICY_SPEC }}</value>
    </property>
</configuration>
