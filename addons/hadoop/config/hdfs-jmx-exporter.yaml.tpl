jmxUrl: service:jmx:rmi:///jndi/rmi://127.0.0.1:{{ .HDFS_JMX_PORT }}/jmxrmi
ssl: false
lowercaseOutputName: true
lowercaseOutputLabelNames: true
whitelistObjectNames:
  - "Hadoop:*"
  - "java.lang:*"
rules:
  - pattern: ".*"
