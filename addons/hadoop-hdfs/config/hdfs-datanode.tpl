<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
    <property>
        <name>dfs.nameservices</name>
        <value>{{ .CLUSTER_NAME }}</value>
    </property>

    <property>
        <name>dfs.datanode.data.dir</name>
        <value>/hadoop/dfs/data0</value>
    </property>

    <property>
        <name>dfs.ha.namenodes.{{ .CLUSTER_NAME }}</name>
        {{- $nns := "" }}
        {{- range $i := until (int .NAMENODE_COMPONENT_REPLICAS) }}
           {{- $val := printf "nn%d" $i }}
           {{- if eq $nns "" }}{{ $nns = $val }}{{ else }}{{ $nns = print $nns "," $val }}{{ end }}
        {{- end }}
        <value>{{ $nns }}</value>
    </property>
  {{- range $i := until (int .NAMENODE_COMPONENT_REPLICAS) }}
    <property>
        <name>dfs.namenode.rpc-address.{{ $.CLUSTER_NAME }}.nn{{ $i }}</name>
        <value>{{ $.CLUSTER_COMPONENT_NAME }}-{{ $i }}.{{ $.CLUSTER_COMPONENT_NAME }}-headless.{{ $.CLUSTER_NAMESPACE }}.svc.{{ $.CLUSTER_DOMAIN }}:8020</value>
    </property>
    <property>
        <name>dfs.namenode.http-address.{{ $.CLUSTER_NAME }}.nn{{ $i }}</name>
        <value>{{ $.CLUSTER_COMPONENT_NAME }}-{{ $i }}.{{ $.CLUSTER_COMPONENT_NAME }}-headless.{{ $.CLUSTER_NAMESPACE }}.svc.{{ $.CLUSTER_DOMAIN }}:9870</value>
    </property>
  {{- end }}
</configuration>
