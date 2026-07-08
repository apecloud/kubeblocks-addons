export JAVA_HOME=${JAVA_HOME:-/usr/local/openjdk-8}
export HADOOP_HOME=${HADOOP_HOME:-/opt/hadoop}
export HADOOP_CONF_DIR=${HADOOP_CONF_DIR:-${HADOOP_HOME}/etc/hadoop}
export HADOOP_LOG_DIR=${HADOOP_LOG_DIR:-/var/log/hadoop}
export HADOOP_PID_DIR=${HADOOP_PID_DIR:-/tmp/hadoop}
export HADOOP_IDENT_STRING=${HADOOP_IDENT_STRING:-$USER}

export HADOOP_OPTS="${HADOOP_OPTS} -Djava.net.preferIPv4Stack=true -Dsun.net.inetaddr.ttl=10 -XX:+UseG1GC -XX:MaxGCPauseMillis=50 -XX:ParallelGCThreads=8"
export HDFS_HA_NAMENODE_IDS="${HDFS_HA_NAMENODE_IDS:-{{ .HDFS_HA_NAMENODE_IDS }}}"
export HADOOP_JMX_BASE="-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=127.0.0.1"

export HDFS_NAMENODE_OPTS="${HDFS_NAMENODE_OPTS:-} $HADOOP_JMX_BASE -Dcom.sun.management.jmxremote.port={{ .HDFS_NAMENODE_JMX_PORT }} -Dcom.sun.management.jmxremote.rmi.port={{ .HDFS_NAMENODE_JMX_PORT }} -Xms{{ .HDFS_NAMENODE_HEAP }} -Xmx{{ .HDFS_NAMENODE_HEAP }} -Dhadoop.security.logger=INFO,RFAS -Dhdfs.audit.logger=INFO,NullAppender"

export HDFS_DATANODE_OPTS="${HDFS_DATANODE_OPTS:-} $HADOOP_JMX_BASE -Dcom.sun.management.jmxremote.port={{ .HDFS_DATANODE_JMX_PORT }} -Dcom.sun.management.jmxremote.rmi.port={{ .HDFS_DATANODE_JMX_PORT }} -Xms{{ .HDFS_DATANODE_HEAP }} -Xmx{{ .HDFS_DATANODE_HEAP }} -Dhadoop.security.logger=ERROR,RFAS -Ddfs.datanode.hostname=${POD_FQDN}"

export HDFS_JOURNALNODE_OPTS="${HDFS_JOURNALNODE_OPTS:-} $HADOOP_JMX_BASE -Dcom.sun.management.jmxremote.port={{ .HDFS_JOURNALNODE_JMX_PORT }} -Dcom.sun.management.jmxremote.rmi.port={{ .HDFS_JOURNALNODE_JMX_PORT }} -Xms{{ .HDFS_JOURNALNODE_HEAP }} -Xmx{{ .HDFS_JOURNALNODE_HEAP }}"

export HDFS_ZKFC_OPTS="${HDFS_ZKFC_OPTS:-} $HADOOP_JMX_BASE -Dcom.sun.management.jmxremote.port={{ .HDFS_ZKFC_JMX_PORT }} -Dcom.sun.management.jmxremote.rmi.port={{ .HDFS_ZKFC_JMX_PORT }} -Xms{{ .HDFS_ZKFC_HEAP }} -Xmx{{ .HDFS_ZKFC_HEAP }}"

export HADOOP_CLIENT_OPTS="${HADOOP_CLIENT_OPTS:-} -Xmx512m"

export LD_LIBRARY_PATH="${HADOOP_HOME}/lib/native:${LD_LIBRARY_PATH:-}"
