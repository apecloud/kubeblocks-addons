<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
      <property>
          <name>fs.defaultFS</name>
          <value>hdfs://{{- .CLUSTER_NAME }}-namenode-0.{{- .CLUSTER_NAME }}-namenode-headless.{{-
              .NAMESPACE }}.svc.{{- .CLUSTER_DOMAIN }}:{{- .HDFS_NAMENODE_RPC_PORT }}</value>
      </property>
</configuration>
