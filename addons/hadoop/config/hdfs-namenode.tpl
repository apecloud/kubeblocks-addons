<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

{{- $fqnds := splitList "," .JOURNALNODE_POD_FQDN_LIST }}
{{- $journalnode_fqdns := printf "qjournal://" }}
{{- $journalnode_rpc_port := .HDFS_JOURNALNODE_RPC_PORT }}
{{- $name_node_ids := splitList "," .HDFS_HA_NAMENODE_IDS }}
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
        <name>dfs.namenode.rpc-bind-host</name>
        <value>0.0.0.0</value>
    </property>
    <property>
        <name>dfs.namenode.http-bind-host</name>
        <value>0.0.0.0</value>
    </property>

    <property>
        <name>dfs.namenode.shared.edits.dir</name>
        <value>{{- $journalnode_fqdns }}</value>
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
        <name>dfs.ha.fencing.ssh.private-key-files</name>
        <value>/var/lib/hadoop-hdfs/.ssh/id_dsa</value>
    </property>

    <property>
        <name>dfs.ha.fencing.ssh.connect-timeout</name>
        <value>{{- .HDFS_HA_FENCING_SSH_CONNECT_TIMEOUT_MS }}</value>
    </property>

    <property>
        <name>dfs.ha.automatic-failover.enabled</name>
        <value>{{- .HDFS_HA_AUTOMATIC_FAILOVER_ENABLED }}</value>
    </property>

    <property>
        <name>dfs.ha.failover-controller.active-standby-elector.zk.op.retries</name>
        <value>{{- .HDFS_HA_ZOOKEEPER_OPERATION_RETRIES }}</value>
    </property>

    <property>
        <name>dfs.permissions.enabled</name>
        <value>{{- .HDFS_PERMISSIONS_ENABLED }}</value>
    </property>

    <property>
        <name>dfs.permissions.superusergroup</name>
        <value>{{- .HDFS_PERMISSIONS_SUPERUSERGROUP }}</value>
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
        <name>dfs.replication.max</name>
        <value>{{- .HDFS_REPLICATION_MAX }}</value>
    </property>

    <property>
        <name>dfs.client.block.write.replace-datanode-on-failure.policy</name>
        <value>{{- .HDFS_CLIENT_REPLACE_DATANODE_ON_FAILURE_POLICY }}</value>
    </property>

    <property>
        <name>dfs.namenode.handler.count</name>
        <value>{{- .HDFS_NAMENODE_HANDLER_COUNT }}</value>
    </property>

    <property>
        <name>dfs.namenode.service.handler.count</name>
        <value>{{- .HDFS_NAMENODE_HANDLER_COUNT }}</value>
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
        <name>dfs.webhdfs.enabled</name>
        <value>{{- .HDFS_NAMENODE_WEBHDFS_ENABLED }}</value>
    </property>

    <property>
        <name>dfs.datanode.block-pinning.enabled</name>
        <value>true</value>
    </property>

    <property>
        <name>dfs.namenode.avoid.read.stale.datanode</name>
        <value>true</value>
    </property>

    <property>
        <name>dfs.namenode.avoid.write.stale.datanode</name>
        <value>true</value>
    </property>

    <property>
        <name>dfs.namenode.resource.du.reserved</name>
        <value>{{- .HDFS_NAMENODE_RESOURCE_DU_RESERVED }}</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.enabled</name>
        <value>{{- .HDFS_CLIENT_RETRY_POLICY_ENABLED }}</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.spec</name>
        <value>{{- .HDFS_CLIENT_RETRY_POLICY_SPEC }}</value>
    </property>

    <property>
        <name>dfs.namenode.stale.datanode.interval</name>
        <value>30000</value>
    </property>

    <property>
        <name>dfs.ha.log-roll.period</name>
        <value>{{- .HDFS_HA_LOG_ROLL_PERIOD }}</value>
    </property>

    <property>
        <name>dfs.ha.tail-edits.period</name>
        <value>{{- .HDFS_HA_TAIL_EDITS_PERIOD }}</value>
    </property>

    <property>
        <name>dfs.image.transfer.bandwidthPerSec</name>
        <value>0</value>
    </property>

    <property>
        <name>dfs.namenode.num.checkpoints.retained</name>
        <value>2</value>
    </property>

    <property>
        <name>dfs.namenode.num.extra.edits.retained</name>
        <value>1000000</value>
    </property>

    <property>
        <name>dfs.journalnode.http-address</name>
        <value>0.0.0.0:8480</value>
    </property>

    <property>
        <name>dfs.journalnode.rpc-address</name>
        <value>0.0.0.0:8485</value>
    </property>
</configuration>