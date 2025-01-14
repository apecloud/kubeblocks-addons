<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
    <property>
        <name>dfs.nameservices</name>
        <value>hdfs-k8s</value>
    </property>
    
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>/hadoop/dfs/data0</value>
    </property>

    <property>
        <name>dfs.ha.namenodes.hdfs-k8s</name>
        <value>nn0,nn1</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-address.hdfs-k8s.nn0</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-0.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:8020</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-address.hdfs-k8s.nn1</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-1.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:8020</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.hdfs-k8s.nn0</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-0.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:9870</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.hdfs-k8s.nn1</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-1.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:9870</value>
    </property>
</configuration>