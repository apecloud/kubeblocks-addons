<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://{{ .HDFS_NAMESERVICE }}</value>
    </property>

    <property>
        <name>fs.trash.interval</name>
        <value>{{ .HDFS_FS_TRASH_INTERVAL }}</value>
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
        <value>{{ .HADOOP_SECURITY_AUTHENTICATION }}</value>
    </property>

    <property>
        <name>hadoop.security.authorization</name>
        <value>{{ .HADOOP_SECURITY_AUTHORIZATION }}</value>
    </property>

    <property>
        <name>ipc.client.connection.maxidletime</name>
        <value>{{ .HADOOP_IPC_CLIENT_CONNECTION_MAXIDLETIME }}</value>
    </property>

    <property>
        <name>ipc.client.connect.timeout</name>
        <value>{{ .HADOOP_IPC_CLIENT_CONNECT_TIMEOUT }}</value>
    </property>

    <property>
        <name>ipc.client.ping</name>
        <value>true</value>
    </property>

    <property>
        <name>ipc.ping.interval</name>
        <value>{{ .HADOOP_IPC_PING_INTERVAL }}</value>
    </property>

    <property>
        <name>hadoop.tmp.dir</name>
        <value>{{ .HADOOP_TMP_DIR }}</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.enabled</name>
        <value>{{ .HDFS_COMMON_CLIENT_RETRY_POLICY_ENABLED }}</value>
    </property>

    <property>
        <name>dfs.client.retry.policy.spec</name>
        <value>{{ .HDFS_COMMON_CLIENT_RETRY_POLICY_SPEC }}</value>
    </property>
</configuration>
