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
        <value>30000</value>
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
        <value>4000</value>
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
        <name>hbase.regionserver.hostname</name>
        <value>{{ .POD_FQDN }}</value>
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
        <value>100</value>
    </property>

    <property>
        <name>hbase.hstore.flusher.count</name>
        <value>4</value>
    </property>

    <property>
        <name>hbase.client.scanner.caching</name>
        <value>100</value>
    </property>

    <property>
        <name>hbase.hregion.max.filesize</name>
        <value>53687091200</value>
    </property>

    <property>
        <name>hbase.hregion.memstore.flush.size</name>
        <value>134217728</value>
    </property>

    <property>
        <name>hbase.hregion.majorcompaction</name>
        <value>0</value>
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
        <value>300000</value>
    </property>

    <property>
        <name>hbase.master.startup.retainassign.timeout</name>
        <value>300000</value>
    </property>

    <property>
        <name>hbase.assignment.usezk</name>
        <value>false</value>
    </property>

    <property>
        <name>hbase.oldwals.cleaner.thread.timeout.msec</name>
        <value>60000</value>
    </property>

    <property>
        <name>hbase.master.logcleaner.ttl</name>
        <value>60000</value>
    </property>

    <property>
        <name>hbase.master.hfilecleaner.ttl</name>
        <value>600000</value>
    </property>

    <property>
        <name>hbase.balancer.period</name>
        <value>1800000</value>
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
        <value>true</value>
    </property>

    <property>
        <name>hbase.regionserver.optionalcacheflushinterval</name>
        <value>28800000</value>
    </property>

    <property>
        <name>hbase.regionserver.startup.retries</name>
        <value>10</value>
    </property>

    <property>
        <name>hbase.regionserver.startup.retry.interval</name>
        <value>10000</value>
    </property>

    <property>
        <name>hbase.wal.provider</name>
        <value>filesystem</value>
    </property>

    <property>
        <name>hbase.replication</name>
        <value>true</value>
    </property>

    <property>
        <name>hbase.security.authentication</name>
        <value>simple</value>
    </property>

    <property>
        <name>hbase.security.authorization</name>
        <value>false</value>
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
        <value>15</value>
    </property>

    <property>
        <name>dfs.client.failover.sleep.base.millis</name>
        <value>500</value>
    </property>

    <property>
        <name>dfs.client.failover.sleep.max.millis</name>
        <value>15000</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.enabled</name>
        <value>true</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.spec</name>
        <value>10000,6,60000,10</value>
    </property>

    <property>
        <name>ipc.client.connect.timeout</name>
        <value>30000</value>
    </property>

    <property>
        <name>ipc.client.connect.max.retries</name>
        <value>10</value>
    </property>

    <property>
        <name>hbase.regionserver.wal.codec</name>
        <value>org.apache.hadoop.hbase.regionserver.wal.IndexedWALEditCodec</value>
    </property>

    <property>
        <name>hbase.regionserver.wal.rs.bulkload.enabled</name>
        <value>true</value>
    </property>

    <property>
        <name>hbase.splitlog.manager.timeout</name>
        <value>600000</value>
    </property>
</configuration>
