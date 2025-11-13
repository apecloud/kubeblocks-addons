<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <!-- ZooKeeper Configuration -->
    <property>
        <name>hbase.zookeeper.quorum</name>
        <value>{{ .ZOOKEEPER_ENDPOINTS }}</value>
        <description>List of ZooKeeper servers, separated by commas</description>
    </property>
    <property>
        <name>hbase.zookeeper.property.clientPort</name>
        <value>2181</value>
        <description>ZooKeeper client port</description>
    </property>

    <!-- Root Directory Configuration -->
    <property>
        <name>hbase.rootdir</name>
        <value>hdfs://{{ .HADOOP_CLUSTER_NAME }}/{{ .CLUSTER_NAME }}</value>
        <description>Root directory of HBase on HDFS. Use file:///hbase for standalone mode. ENV_HADOOP_CLUSTER_NAME will be replaced in init scripts.</description>
    </property>

    <!-- Cluster Mode Configuration -->
    <property>
        <name>hbase.cluster.distributed</name>
        <value>true</value>
        <description>Whether to enable distributed mode. Set to false for standalone mode</description>
    </property>

    <!-- Master Configuration -->
    <property>
        <name>hbase.master.port</name>
        <value>16000</value>
    </property>
    <property>
        <name>hbase.master.info.port</name>
        <value>16010</value>
        <description>HBase Master web UI port</description>
    </property>

    <!-- RegionServer Configuration -->
    <property>
        <name>hbase.regionserver.hostname</name>
        <value></value>
    </property>
    <property>
        <name>hbase.regionserver.port</name>
        <value>16020</value>
    </property>
    <property>
        <name>hbase.regionserver.info.port</name>
        <value>16030</value>
        <description>RegionServer web UI port</description>
    </property>

    <!-- Memory Configuration -->
    <property>
        <name>hbase.regionserver.handler.count</name>
        <value>30</value>
        <description>Number of RPC handler threads for RegionServer</description>
    </property>
    <property>
        <name>hbase.client.scanner.caching</name>
        <value>100</value>
        <description>Number of rows cached by the scanner</description>
    </property>

    <!-- Temporary Directory -->
    <property>
        <name>hbase.tmp.dir</name>
        <value>/hbase/temp</value>
        <description>Temporary file directory</description>
    </property>

    <!-- Security Configuration -->
    <property>
        <name>hbase.security.authentication</name>
        <value>simple</value>
        <description>Authentication mode: simple or kerberos</description>
    </property>

    <!-- Compression Configuration -->
    <property>
        <name>hbase.table.compression.algorithm</name>
        <value>SNAPPY</value>
        <description>Default compression algorithm</description>
    </property>

    <!-- Replication Configuration -->
    <property>
        <name>hbase.replication</name>
        <value>true</value>
        <description>Whether to enable replication</description>
    </property>

    <property>
        <name>hbase.region.replica.replication.num</name>
        <value>2</value> <!-- Primary replica + 2 replicas, total of 3 -->
    </property>

    <!-- Performance Optimization -->
    <property>
        <name>hbase.hregion.max.filesize</name>
        <value>10737418240</value>
        <description>Region split threshold, default 10GB</description>
    </property>
    <property>
        <name>hbase.hregion.memstore.flush.size</name>
        <value>134217728</value>
        <description>Memstore flush threshold, default 128MB</description>
    </property>

    <property>
        <name>hbase.wal.provider</name>
        <value>filesystem</value>
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
        <name>hbase.master.wait.on.regionservers.timeout</name>
        <value>300000</value>
    </property>

    <property>
        <name>hbase.master.startup.retainassign.timeout</name>
        <value>300000</value>
    </property>
</configuration>
