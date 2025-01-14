<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

{{- $fqnds := splitList "," .JOURNALNODE_POD_FQDN_LIST }}
{{- $journalnode_fqdns := printf "qjournal://" }}
{{- range $i, $fqdn := $fqnds }}
  {{- $journalnode_fqdns = printf "%s%s:8485" $journalnode_fqdns $fqdn }}
  {{- if lt $i (sub (len $fqnds) 1) }}
    {{- $journalnode_fqdns = printf "%s;" $journalnode_fqdns }}
  {{- end }}
{{- end }}
{{- $journalnode_fqdns = printf "%s/k8scluster" $journalnode_fqdns }}

<configuration>
    <property>
        <name>dfs.nameservices</name>
        <value>k8scluster</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>/hadoop/dfs/metadata</value>
    </property>
    <property>
        <name>dfs.ha.namenodes.k8scluster</name>
        <value>nn0,nn1</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-address.k8scluster.nn0</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-0.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:8020</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-address.k8scluster.nn1</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-1.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:8020</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.k8scluster.nn0</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-0.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:9870</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.k8scluster.nn1</name>
        <value>{{- .KB_CLUSTER_NAME }}-namenode-1.{{- .KB_CLUSTER_NAME }}-namenode-headless.{{- .KB_NAMESPACE }}.svc.cluster.local:9870</value>
    </property>
    <property>
        <name>dfs.namenode.shared.edits.dir</name>
        <value>
            {{- $journalnode_fqdns }}
        </value>
    </property>
    <property>
        <name>dfs.client.failover.proxy.provider.k8scluster</name>
        <value>org.apache.hadoop.hdfs.server.namenode.ha.ConfiguredFailoverProxyProvider</value>
    </property>
    <property>
        <name>dfs.ha.fencing.methods</name>
        <value>shell(/bin/true)</value>
    </property>
    <property>
        <name>dfs.ha.automatic-failover.enabled</name>
        <value>true</value>
    </property>
    <property>
        <name>dfs.permissions.enable</name>
        <value>false</value>
    </property>
    <property>
        <name>dfs.namenode.datanode.registration.ip-hostname-check</name>
        <value>false</value>
    </property>
    </configuration>