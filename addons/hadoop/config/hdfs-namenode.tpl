<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

{{- $fqnds := splitList "," .JOURNALNODE_POD_FQDN_LIST }}
{{- $journalnode_fqdns := printf "qjournal://" }}
{{- range $i, $fqdn := $fqnds }}
  {{- $journalnode_fqdns = printf "%s%s:8485" $journalnode_fqdns $fqdn }}
  {{- if lt $i (sub (len $fqnds) 1) }}
    {{- $journalnode_fqdns = printf "%s;" $journalnode_fqdns }}
  {{- end }}
{{- end }}
{{- $journalnode_fqdns = printf "%s/%s" $journalnode_fqdns .KB_CLUSTER_NAME }}

<configuration>
    <property>
        <name>dfs.nameservices</name>
        <value>{{- .KB_CLUSTER_NAME }}</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>/hadoop/dfs/metadata</value>
    </property>
    <property>
        <name>dfs.ha.namenodes.{{- .KB_CLUSTER_NAME }}</name>
        <value>nn0,nn1</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-address.{{- .KB_CLUSTER_NAME }}.nn0</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-0.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:8020</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-address.{{- .KB_CLUSTER_NAME }}.nn1</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-1.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:8020</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.{{- .KB_CLUSTER_NAME }}.nn0</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-0.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:9870</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.{{- .KB_CLUSTER_NAME }}.nn1</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-1.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:9870</value>
    </property>
    <property>
        <name>dfs.namenode.shared.edits.dir</name>
        <value>
            {{- $journalnode_fqdns }}
        </value>
    </property>
    <property>
        <name>dfs.client.failover.proxy.provider.{{- .KB_CLUSTER_NAME }}</name>
        <value>org.apache.hadoop.hdfs.server.namenode.ha.ConfiguredFailoverProxyProvider</value>
    </property>
    <property>
        <name>dfs.ha.fencing.methods</name>
        <value>shell(/bin/true)</value>
    </property>
    <property>
        <name>dfs.ha.automatic-failover.enabled</name>
        <value>true</value>
    </property>
    <property>
        <name>dfs.permissions.enable</name>
        <value>false</value>
    </property>
    <property>
        <name>dfs.namenode.datanode.registration.ip-hostname-check</name>
        <value>false</value>
    </property>

    <!-- 2. 自动故障转移相关的 ZK 配置 -->
    <property>
        <name>dfs.ha.automatic-failover.enabled</name>
        <value>true</value>
    </property>

    <property>
        <name>ha.zookeeper.quorum</name>
        <value>{{- .ZOOKEEPER_ENDPOINTS }}</value>
    </property>
    
    <!-- 3. ZK 会话超时设置 -->
    <property>
        <name>ha.zookeeper.session-timeout.ms</name>
        <value>60000</value>
    </property>

    <!-- 4. ZK 重试次数 -->
    <property>
        <name>ha.failover-controller.active-standby-elector.zk.op.retries</name>
        <value>3</value>
    </property>

   <!-- IPC 连接保持时间 -->
    <property>
        <name>ipc.client.connection.maxidletime</name>
        <value>300000</value>  <!-- 5分钟 -->
    </property>
    
    <!-- IPC 连接超时时间 -->
    <property>
        <name>ipc.client.connect.timeout</name>
        <value>20000</value>  <!-- 20秒 -->
    </property>
    
    <!-- IPC 连接池大小 -->
    <property>
        <name>ipc.client.connection.pool.size</name>
        <value>8</value>
    </property>
    
    <!-- 连接重试间隔 -->
    <property>
        <name>ipc.client.connect.retry.interval</name>
        <value>1000</value>
    </property>
    
    <!-- 保持连接存活配置 -->
    <property>
        <name>ipc.client.ping</name>
        <value>true</value>
    </property>
    
    <!-- 心跳间隔 -->
    <property>
        <name>ipc.ping.interval</name>
        <value>30000</value>  <!-- 30秒 -->
    </property>
</configuration>
