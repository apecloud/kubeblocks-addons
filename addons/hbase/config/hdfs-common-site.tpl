<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://{{ .HDFS_NAMESERVICE }}</value>
    </property>

    <property>
        <name>fs.trash.interval</name>
        <value>1440</value>
    </property>

    <property>
        <name>io.compression.codecs</name>
        <value>org.apache.hadoop.io.compress.GzipCodec,org.apache.hadoop.io.compress.DefaultCodec,org.apache.hadoop.io.compress.BZip2Codec,org.apache.hadoop.io.compress.SnappyCodec</value>
    </property>

    <property>
        <name>ha.zookeeper.quorum</name>
        <value>{{ .ZOOKEEPER_ENDPOINTS }}</value>
    </property>

    <property>
        <name>ha.zookeeper.parent-znode</name>
        <value>{{ .HDFS_HA_ZK_PARENT }}</value>
    </property>

    <property>
        <name>hadoop.http.staticuser.user</name>
        <value>hbase</value>
    </property>

    <property>
        <name>hadoop.security.authentication</name>
        <value>simple</value>
    </property>

    <property>
        <name>hadoop.security.authorization</name>
        <value>false</value>
    </property>

    <property>
        <name>ipc.client.connection.maxidletime</name>
        <value>30000</value>
    </property>

    <property>
        <name>ipc.client.connect.timeout</name>
        <value>10000</value>
    </property>

    <property>
        <name>ipc.client.ping</name>
        <value>true</value>
    </property>

    <property>
        <name>ipc.ping.interval</name>
        <value>60000</value>
    </property>

    <property>
        <name>hadoop.tmp.dir</name>
        <value>/hadoop/tmp</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.enabled</name>
        <value>true</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.spec</name>
        <value>1000,1</value>
    </property>
</configuration>
