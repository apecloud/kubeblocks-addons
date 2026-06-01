<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

{{- $fqnds := splitList "," .JOURNALNODE_POD_FQDN_LIST }}
{{- $journalnode_fqdns := printf "qjournal://" }}
{{- $journalnode_rpc_port := .HDFS_JOURNALNODE_RPC_PORT }}
{{- range $i, $fqdn := $fqnds }}
{{- $journalnode_fqdns = printf "%s%s:%s" $journalnode_fqdns $fqdn $journalnode_rpc_port }}
{{- if lt $i (sub (len $fqnds) 1) }}
{{- $journalnode_fqdns = printf "%s;" $journalnode_fqdns }}
{{- end }}
{{- end }}
{{- $journalnode_fqdns = printf "%s/%s" $journalnode_fqdns .CLUSTER_NAME }}

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
        <name>dfs.namenode.shared.edits.dir</name>
        <value>
            {{- $journalnode_fqdns }}
        </value>
    </property>
    <property>
        <name>dfs.client.failover.proxy.provider.{{- .CLUSTER_NAME }}</name>
        <value>org.apache.hadoop.hdfs.server.namenode.ha.ConfiguredFailoverProxyProvider</value>
    </property>
    <property>
        <name>dfs.ha.fencing.methods</name>
        <value>{{- .HDFS_HA_FENCING_METHODS }}</value>
    </property>
    <property>
        <name>dfs.ha.automatic-failover.enabled</name>
        <value>{{- .HDFS_HA_AUTOMATIC_FAILOVER_ENABLED }}</value>
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

    <!-- 2. 自动故障转移相关的 ZK 配置 -->
    <property>
        <name>dfs.ha.automatic-failover.enabled</name>
        <value>{{- .HDFS_HA_AUTOMATIC_FAILOVER_ENABLED }}</value>
    </property>

    <property>
        <name>ha.zookeeper.quorum</name>
        <value>{{- .ZOOKEEPER_ENDPOINTS }}</value>
    </property>
    <property>
        <name>ha.zookeeper.parent-znode</name>
        <value>{{- .HDFS_HA_ZOOKEEPER_PARENT_ZNODE_PREFIX }}/{{- .CLUSTER_NAME }}{{- if eq
            .HDFS_HA_ZOOKEEPER_INCLUDE_CLUSTER_UID "true" }}-{{- .CLUSTER_UID }}{{- end }}</value>
    </property>

    <!-- 3. ZK 会话超时设置 -->
    <property>
        <name>ha.zookeeper.session-timeout.ms</name>
        <value>{{- .HDFS_HA_ZOOKEEPER_SESSION_TIMEOUT_MS }}</value>
    </property>

    <!-- 4. ZK 重试次数 -->
    <property>
        <name>ha.failover-controller.active-standby-elector.zk.op.retries</name>
        <value>{{- .HDFS_HA_ZOOKEEPER_OPERATION_RETRIES }}</value>
    </property>

    <!-- IPC 连接保持时间 -->
    <property>
        <name>ipc.client.connection.maxidletime</name>
        <value>{{- .HDFS_IPC_CLIENT_CONNECTION_MAX_IDLE_TIME_MS }}</value>
    </property>

    <!-- IPC 连接超时时间 -->
    <property>
        <name>ipc.client.connect.timeout</name>
        <value>{{- .HDFS_IPC_CLIENT_CONNECT_TIMEOUT_MS }}</value>
    </property>

    <!-- IPC 连接池大小 -->
    <property>
        <name>ipc.client.connection.pool.size</name>
        <value>{{- .HDFS_IPC_CLIENT_CONNECTION_POOL_SIZE }}</value>
    </property>

    <!-- 连接重试间隔 -->
    <property>
        <name>ipc.client.connect.retry.interval</name>
        <value>{{- .HDFS_IPC_CLIENT_CONNECT_RETRY_INTERVAL_MS }}</value>
    </property>

    <!-- 保持连接存活配置 -->
    <property>
        <name>ipc.client.ping</name>
        <value>{{- .HDFS_IPC_CLIENT_PING }}</value>
    </property>

    <!-- 心跳间隔 -->
    <property>
        <name>ipc.ping.interval</name>
        <value>{{- .HDFS_IPC_PING_INTERVAL_MS }}</value>
    </property>
</configuration>
