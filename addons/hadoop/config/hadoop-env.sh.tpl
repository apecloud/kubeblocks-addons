export JAVA_HOME=${JAVA_HOME:-/usr/local/openjdk-8}
export HADOOP_HOME=${HADOOP_HOME:-/opt/hadoop}
export HADOOP_CONF_DIR=${HADOOP_CONF_DIR:-${HADOOP_HOME}/etc/hadoop}
export HADOOP_LOG_DIR=${HADOOP_LOG_DIR:-/var/log/hadoop}
export HADOOP_PID_DIR=${HADOOP_PID_DIR:-/tmp/hadoop}
export HADOOP_IDENT_STRING=${HADOOP_IDENT_STRING:-$USER}

export HADOOP_OPTS="${HADOOP_OPTS} -Djava.net.preferIPv4Stack=true -Dsun.net.inetaddr.ttl=10 -XX:+UseG1GC -XX:MaxGCPauseMillis=50 -XX:ParallelGCThreads=8"

export HDFS_NAMENODE_OPTS="${HDFS_NAMENODE_OPTS:-} -Xms{{ .HDFS_NAMENODE_HEAP }} -Xmx{{ .HDFS_NAMENODE_HEAP }} -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Dhadoop.security.logger=INFO,RFAS -Dhdfs.audit.logger=INFO,NullAppender"

export HDFS_DATANODE_OPTS="${HDFS_DATANODE_OPTS:-} -Xms{{ .HDFS_DATANODE_HEAP }} -Xmx{{ .HDFS_DATANODE_HEAP }} -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Dhadoop.security.logger=ERROR,RFAS"

export HDFS_JOURNALNODE_OPTS="${HDFS_JOURNALNODE_OPTS:-} -Xms{{ .HDFS_JOURNALNODE_HEAP }} -Xmx{{ .HDFS_JOURNALNODE_HEAP }} -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"

export HDFS_ZKFC_OPTS="${HDFS_ZKFC_OPTS:-} -Xms{{ .HDFS_ZKFC_HEAP }} -Xmx{{ .HDFS_ZKFC_HEAP }} -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"

export HADOOP_CLIENT_OPTS="${HADOOP_CLIENT_OPTS:-} -Xmx512m"

export LD_LIBRARY_PATH="${HADOOP_HOME}/lib/native:${LD_LIBRARY_PATH:-}"
