<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>hbase.cluster.distributed</name>
        <value>false</value>
    </property>

    <property>
        <name>hbase.rootdir</name>
        <value>file://{{ .HBASE_DATA_DIR }}/hbase</value>
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
        <name>hbase.unsafe.stream.capability.enforce</name>
        <value>false</value>
    </property>

    <property>
        <name>hbase.procedure.store.wal.use.hsync</name>
        <value>{{ .HBASE_PROCEDURE_STORE_WAL_USE_HSYNC }}</value>
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
        <name>hbase.io.compress.lz4.codec</name>
        <value>org.apache.hadoop.hbase.io.compress.lz4.Lz4Codec</value>
    </property>

    <property>
        <name>hbase.security.authentication</name>
        <value>{{ .HBASE_SECURITY_AUTHENTICATION }}</value>
    </property>

    <property>
        <name>hbase.security.authorization</name>
        <value>{{ .HBASE_SECURITY_AUTHORIZATION }}</value>
    </property>
</configuration>
