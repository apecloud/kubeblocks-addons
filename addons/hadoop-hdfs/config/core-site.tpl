<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
      <property>
          <name>fs.defaultFS</name>
          <value>hdfs://k8scluster</value>
      </property>
      <property>
          <name>ha.zookeeper.quorum</name>
          <value>{{- .ZOOKEEPER_ENDPOINTS }}</value>
      </property>
</configuration>