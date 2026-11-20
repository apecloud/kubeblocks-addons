<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://{{- .CLUSTER_NAME }}-namenode-0.{{- .CLUSTER_NAME }}-namenode-headless.{{-
            .NAMESPACE }}.svc.{{- .CLUSTER_DOMAIN }}:{{- .HDFS_NAMENODE_RPC_PORT }}</value>
    </property>

    <property>
        <name>fs.trash.interval</name>
        <value>{{- .HDFS_TRASH_INTERVAL }}</value>
    </property>

    <property>
        <name>io.compression.codecs</name>
        <value>
            org.apache.hadoop.io.compress.GzipCodec,org.apache.hadoop.io.compress.DefaultCodec,org.apache.hadoop.io.compress.BZip2Codec,org.apache.hadoop.io.compress.SnappyCodec,org.apache.hadoop.io.compress.Lz4Codec</value>
    </property>

    <property>
        <name>hadoop.http.staticuser.user</name>
        <value>hdfs</value>
    </property>

    <property>
        <name>hadoop.security.authentication</name>
        <value>{{- .HDFS_SECURITY_AUTHENTICATION }}</value>
    </property>

    <property>
        <name>hadoop.security.authorization</name>
        <value>{{- .HDFS_SECURITY_AUTHORIZATION }}</value>
    </property>

    <property>
        <name>ipc.client.connection.maxidletime</name>
        <value>{{- .HDFS_IPC_CLIENT_CONNECTION_MAX_IDLE_TIME_MS }}</value>
    </property>

    <property>
        <name>ipc.client.connect.timeout</name>
        <value>{{- .HDFS_IPC_CLIENT_CONNECT_TIMEOUT_MS }}</value>
    </property>

    <property>
        <name>ipc.client.connection.pool.size</name>
        <value>{{- .HDFS_IPC_CLIENT_CONNECTION_POOL_SIZE }}</value>
    </property>

    <property>
        <name>ipc.client.connect.retry.interval</name>
        <value>{{- .HDFS_IPC_CLIENT_CONNECT_RETRY_INTERVAL_MS }}</value>
    </property>

    <property>
        <name>ipc.client.ping</name>
        <value>{{- .HDFS_IPC_CLIENT_PING }}</value>
    </property>

    <property>
        <name>ipc.ping.interval</name>
        <value>{{- .HDFS_IPC_PING_INTERVAL_MS }}</value>
    </property>

    <property>
        <name>hadoop.tmp.dir</name>
        <value>{{- .HDFS_HADOOP_TMP_DIR }}</value>
    </property>
</configuration>