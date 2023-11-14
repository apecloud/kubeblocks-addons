<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
    <property>
        <name>hbase.cluster.distributed</name>
        <value>true</value>
    </property>
    <property>
        <name>hbase.rootdir</name>
        <value>hdfs://hdfs-k8s:8020/hbase</value>
    </property>
    <property>
        <name>hbase.zookeeper.quorum</name>
        <value>zk-zookeeper-0.zk-zookeeper-headless.default.svc.cluster.local,zk-zookeeper-0.zk-zookeeper-headless.default.svc.cluster.local,zk-zookeeper-0.zk-zookeeper-headless.default.svc.cluster.local</value>
    </property>
    <property>
        <name>hbase.zookeeper.property.clientPort</name>
        <value>2181</value>
    </property>
    <property>
        <name>hbase.unsafe.stream.capability.enforce</name>
        <value>false</value>
    </property>
    <property>
        <name>zookeeper.session.timeout</name>
        <value>30000</value>
    </property>
    <property>
        <name>hbase.regionserver.handler.count</name>
        <value>90</value>
    </property>
    <property>
        <name>hbase.client.write.buffer</name>
        <value>20971520</value>
    </property>
</configuration>