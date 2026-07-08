<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>hbase.cluster.distributed</name>
        <value>true</value>
    </property>

    <property>
        <name>hbase.rootdir</name>
        <value>hdfs://{{ .HDFS_NAMESERVICE }}/{{ .HBASE_ROOT_DIR }}</value>
    </property>

    <property>
        <name>hbase.zookeeper.quorum</name>
        <value>{{ .ZOOKEEPER_QUORUM }}</value>
    </property>

    <property>
        <name>hbase.zookeeper.property.clientPort</name>
        <value>{{ .ZOOKEEPER_CLIENT_PORT }}</value>
    </property>

    <property>
        <name>zookeeper.znode.parent</name>
        <value>{{ .HBASE_ZK_PARENT }}</value>
    </property>

    <property>
        <name>zookeeper.session.timeout</name>
        <value>{{ .HBASE_ZOOKEEPER_SESSION_TIMEOUT }}</value>
    </property>

    <property>
        <name>hbase.zookeeper.property.tickTime</name>
        <value>6000</value>
    </property>

    <property>
        <name>hbase.zookeeper.property.4lw.commands.whitelist</name>
        <value>*</value>
    </property>

    <property>
        <name>hbase.zookeeper.property.maxClientCnxns</name>
        <value>{{ .HBASE_ZOOKEEPER_MAX_CLIENT_CNXNS }}</value>
    </property>

    <property>
        <name>hbase.zookeeper.property.autopurge.purgeInterval</name>
        <value>1</value>
    </property>

    <property>
        <name>hbase.zookeeper.property.autopurge.snapRetainCount</name>
        <value>3</value>
    </property>

    <property>
        <name>hbase.master.port</name>
        <value>{{ .HBASE_MASTER_PORT }}</value>
    </property>

    <property>
        <name>hbase.master.info.port</name>
        <value>{{ .HBASE_MASTER_INFO_PORT }}</value>
    </property>

    <property>
        <name>hbase.regionserver.port</name>
        <value>{{ .HBASE_REGIONSERVER_PORT }}</value>
    </property>

    <property>
        <name>hbase.regionserver.info.port</name>
        <value>{{ .HBASE_REGIONSERVER_INFO_PORT }}</value>
    </property>

    <property>
        <name>hbase.regionserver.hostname.disable.master.reversedns</name>
        <value>true</value>
    </property>

    <property>
        <name>hbase.tmp.dir</name>
        <value>{{ .HBASE_TMP_DIR }}</value>
    </property>

    <property>
        <name>hbase.regionserver.handler.count</name>
        <value>{{ .HBASE_REGIONSERVER_HANDLER_COUNT }}</value>
    </property>

    <property>
        <name>hbase.hstore.flusher.count</name>
        <value>{{ .HBASE_HSTORE_FLUSHER_COUNT }}</value>
    </property>

    <property>
        <name>hbase.client.scanner.caching</name>
        <value>{{ .HBASE_CLIENT_SCANNER_CACHING }}</value>
    </property>

    <property>
        <name>hbase.hregion.max.filesize</name>
        <value>{{ .HBASE_HREGION_MAX_FILESIZE }}</value>
    </property>

    <property>
        <name>hbase.hregion.memstore.flush.size</name>
        <value>{{ .HBASE_HREGION_MEMSTORE_FLUSH_SIZE }}</value>
    </property>

    <property>
        <name>hbase.hregion.majorcompaction</name>
        <value>{{ .HBASE_HREGION_MAJORCOMPACTION }}</value>
    </property>

    <property>
        <name>hbase.storescanner.parallel.seek.enable</name>
        <value>true</value>
    </property>

    <property>
        <name>hbase.ipc.server.callqueue.type</name>
        <value>plunger</value>
    </property>

    <property>
        <name>hbase.master.wait.on.regionservers.timeout</name>
        <value>{{ .HBASE_MASTER_WAIT_ON_REGIONSERVERS_TIMEOUT }}</value>
    </property>

    <property>
        <name>hbase.master.startup.retainassign.timeout</name>
        <value>{{ .HBASE_MASTER_STARTUP_RETAINASSIGN_TIMEOUT }}</value>
    </property>

    <property>
        <name>hbase.assignment.usezk</name>
        <value>false</value>
    </property>

    <property>
        <name>hbase.oldwals.cleaner.thread.timeout.msec</name>
        <value>{{ .HBASE_OLDWALS_CLEANER_THREAD_TIMEOUT_MSEC }}</value>
    </property>

    <property>
        <name>hbase.master.logcleaner.ttl</name>
        <value>{{ .HBASE_MASTER_LOGCLEANER_TTL }}</value>
    </property>

    <property>
        <name>hbase.master.hfilecleaner.ttl</name>
        <value>{{ .HBASE_MASTER_HFILECLEANER_TTL }}</value>
    </property>

    <property>
        <name>hbase.balancer.period</name>
        <value>{{ .HBASE_BALANCER_PERIOD }}</value>
    </property>

    <property>
        <name>hbase.master.balancer.stochastic.runMaxSteps</name>
        <value>true</value>
    </property>

    <property>
        <name>hbase.master.loadbalancer.class</name>
        <value>org.apache.hadoop.hbase.rsgroup.RSGroupBasedLoadBalancer</value>
    </property>

    <property>
        <name>hbase.procedure.store.wal.use.hsync</name>
        <value>{{ .HBASE_PROCEDURE_STORE_WAL_USE_HSYNC }}</value>
    </property>

    <property>
        <name>hbase.regionserver.optionalcacheflushinterval</name>
        <value>{{ .HBASE_REGIONSERVER_OPTIONALCACHEFLUSHINTERVAL }}</value>
    </property>

    <property>
        <name>hbase.regionserver.startup.retries</name>
        <value>{{ .HBASE_REGIONSERVER_STARTUP_RETRIES }}</value>
    </property>

    <property>
        <name>hbase.regionserver.startup.retry.interval</name>
        <value>{{ .HBASE_REGIONSERVER_STARTUP_RETRY_INTERVAL }}</value>
    </property>

    <property>
        <name>hbase.wal.provider</name>
        <value>filesystem</value>
    </property>

    <property>
        <name>hbase.replication</name>
        <value>{{ .HBASE_REPLICATION_ENABLED }}</value>
    </property>

    <property>
        <name>hbase.security.authentication</name>
        <value>{{ .HBASE_SECURITY_AUTHENTICATION }}</value>
    </property>

    <property>
        <name>hbase.security.authorization</name>
        <value>{{ .HBASE_SECURITY_AUTHORIZATION }}</value>
    </property>

    <property>
        <name>hbase.unsafe.stream.capability.enforce</name>
        <value>false</value>
    </property>

    <property>
        <name>hbase.master.logcleaner.plugins</name>
        <value>
            org.apache.hadoop.hbase.master.cleaner.TimeToLiveLogCleaner,org.apache.hadoop.hbase.master.cleaner.TimeToLiveProcedureWALCleaner,org.apache.hadoop.hbase.replication.master.ReplicationLogCleaner</value>
    </property>

    <property>
        <name>hbase.master.hfilecleaner.plugins</name>
        <value>org.apache.hadoop.hbase.master.cleaner.TimeToLiveHFileCleaner</value>
    </property>

    <property>
        <name>hbase.master.procedure.tlogcleaner.plugins</name>
        <value>org.apache.hadoop.hbase.master.cleaner.TimeToLiveProcedureWALCleaner</value>
    </property>

    <property>
        <name>hbase.coprocessor.master.classes</name>
        <value>
            org.apache.hadoop.hbase.coprocessor.MultiRowMutationEndpoint,org.apache.hadoop.hbase.rsgroup.RSGroupAdminEndpoint</value>
    </property>

    <property>
        <name>hbase.coprocessor.regionserver.classes</name>
        <value>org.apache.hadoop.hbase.coprocessor.MultiRowMutationEndpoint</value>
    </property>

    <property>
        <name>dfs.client.failover.max.attempts</name>
        <value>{{ .HDFS_CLIENT_FAILOVER_MAX_ATTEMPTS }}</value>
    </property>

    <property>
        <name>dfs.client.failover.sleep.base.millis</name>
        <value>{{ .HDFS_CLIENT_FAILOVER_SLEEP_BASE_MILLIS }}</value>
    </property>

    <property>
        <name>dfs.client.failover.sleep.max.millis</name>
        <value>{{ .HDFS_CLIENT_FAILOVER_SLEEP_MAX_MILLIS }}</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.enabled</name>
        <value>{{ .HBASE_HDFS_CLIENT_RETRY_POLICY_ENABLED }}</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.spec</name>
        <value>{{ .HBASE_HDFS_CLIENT_RETRY_POLICY_SPEC }}</value>
    </property>

    <property>
        <name>ipc.client.connect.timeout</name>
        <value>{{ .HBASE_IPC_CLIENT_CONNECT_TIMEOUT }}</value>
    </property>

    <property>
        <name>ipc.client.connect.max.retries</name>
        <value>{{ .HBASE_IPC_CLIENT_CONNECT_MAX_RETRIES }}</value>
    </property>

    <property>
        <name>hbase.regionserver.wal.rs.bulkload.enabled</name>
        <value>true</value>
    </property>

    <property>
        <name>hbase.splitlog.manager.timeout</name>
        <value>{{ .HBASE_SPLITLOG_MANAGER_TIMEOUT }}</value>
    </property>
</configuration>