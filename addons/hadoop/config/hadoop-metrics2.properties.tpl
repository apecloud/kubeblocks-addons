# Hadoop Metrics 2 configuration - JMX sink for all components
*.sink.jmx.class=org.apache.hadoop.metrics2.sink.JmxSink
*.sink.jmx.period=10

# NameNode metrics
namenode.sink.jmx.class=org.apache.hadoop.metrics2.sink.JmxSink
namenode.sink.jmx.period=10

# DataNode metrics
datanode.sink.jmx.class=org.apache.hadoop.metrics2.sink.JmxSink
datanode.sink.jmx.period=10

# JournalNode metrics
journalnode.sink.jmx.class=org.apache.hadoop.metrics2.sink.JmxSink
journalnode.sink.jmx.period=10

# ZKFC metrics
zkfc.sink.jmx.class=org.apache.hadoop.metrics2.sink.JmxSink
zkfc.sink.jmx.period=10
