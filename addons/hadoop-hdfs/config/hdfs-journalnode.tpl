<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
    <property>
        <name>dfs.nameservices</name>
        <value>{{- .KB_CLUSTER_NAME }}</value>
    </property>
    <property>
        <name>dfs.journalnode.edits.dir</name>
        <value>/hadoop/dfs/journal</value>
    </property>
    <!-- JournalNode 基本配置 -->
    <property>
        <name>dfs.journalnode.rpc-address</name>
        <value>0.0.0.0:8485</value>
    </property>
    
    <property>
        <name>dfs.journalnode.http-address</name>
        <value>0.0.0.0:8480</value>
    </property>

    <!-- JMX 配置 -->
    <property>
        <name>hadoop.jmx.enabled</name>
        <value>true</value>
    </property>
</configuration>
