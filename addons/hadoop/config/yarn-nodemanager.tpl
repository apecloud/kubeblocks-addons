<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
    <property>
        <name>yarn.resourcemanager.cluster-id</name>
        <value>{{ .CLUSTER_NAME }}</value>
    </property>
    <property>
        <name>yarn.resourcemanager.ha.enabled</name>
        <value>true</value>
    </property>
    <property>
        <name>yarn.nodemanager.bind-host</name>
        <value>0.0.0.0</value>
    </property>
    <property>
        <name>yarn.resourcemanager.ha.rm-ids</name>
        {{- $rms := "" }}
        {{- range $i := until (int .RESOURCEMANAGER_COMPONENT_REPLICAS) }}
           {{- $val := printf "rm%d" $i }}
           {{- if eq $rms "" }}{{ $rms = $val }}{{ else }}{{ $rms = print $rms "," $val }}{{ end }}
        {{- end }}
        <value>{{ $rms }}</value>
    </property>

  {{- range $i := until (int .RESOURCEMANAGER_COMPONENT_REPLICAS) }}
    <property>
        <name>yarn.resourcemanager.hostname.rm{{ $i }}</name>
        <value>{{ $.RESOURCEMANAGER_CLUSTER_COMPONENT_NAME }}-{{ $i }}.{{ $.RESOURCEMANAGER_CLUSTER_COMPONENT_NAME }}-headless.{{ $.CLUSTER_NAMESPACE }}.svc.{{ $.CLUSTER_DOMAIN }}</value>
    </property>
    <property>
        <name>yarn.resourcemanager.address.rm{{ $i }}</name>
        <value>{{ $.RESOURCEMANAGER_CLUSTER_COMPONENT_NAME }}-{{ $i }}.{{ $.RESOURCEMANAGER_CLUSTER_COMPONENT_NAME }}-headless.{{ $.CLUSTER_NAMESPACE }}.svc.{{ $.CLUSTER_DOMAIN }}:8032</value>
    </property>
  {{- end }}

    <property>
        <name>yarn.nodemanager.recovery.enabled</name>
        <value>true</value>
    </property>

    <property>
        <name>yarn.log-aggregation-enable</name>
        <value>true</value>
    </property>

    <property>
        <name>yarn.nodemanager.recovery.dir</name>
        <value>/hadoop/yarn/yarn-nm-recovery</value>
    </property>

    <property>
        <name>yarn.nodemanager.address</name>
        <value>0.0.0.0:45454</value>
    </property>

    <property>
        <name>yarn.nodemanager.recovery.supervised</name>
        <value>true</value>
    </property>

    <property>
        <name>yarn.nodemanager.container-log-monitor.enable</name>
        <value>true</value>
    </property>

    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>

    <property>
        <name>yarn.nodemanager.aux-services.mapreduce_shuffle.class</name>
        <value>org.apache.hadoop.mapred.ShuffleHandler</value>
    </property>

</configuration>
