export HBASE_CONF_DIR={{ .HBASE_CONF_DIR }}
export HBASE_PID_DIR={{ .HBASE_PID_DIR }}
export HBASE_LOG_DIR={{ .HBASE_LOG_DIR }}
export HBASE_MANAGES_ZK=false

export HBASE_OPTS="${HBASE_OPTS:-} -XX:+UseG1GC -XX:MaxGCPauseMillis=50 -XX:ParallelGCThreads=20 -Dsun.net.inetaddr.ttl=10 -Djava.net.preferIPv4Stack=true"
export SERVER_GC_OPTS="-verbose:gc -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:${HBASE_LOG_DIR}/gc-server.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=5 -XX:GCLogFileSize=50M"
export CLIENT_GC_OPTS="-verbose:gc -XX:+PrintGCDetails -XX:+PrintGCDateStamps"

export HBASE_JMX_BASE="-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false -Djava.rmi.server.hostname=127.0.0.1"
export HBASE_MASTER_OPTS="$HBASE_MASTER_OPTS $HBASE_JMX_BASE -Dcom.sun.management.jmxremote.port={{ .HBASE_MASTER_JMX_PORT }} -Dcom.sun.management.jmxremote.rmi.port={{ .HBASE_MASTER_JMX_PORT }} -Xms{{ .HBASE_MASTER_HEAP_SIZE }} -Xmx{{ .HBASE_MASTER_HEAP_SIZE }}"
export HBASE_REGIONSERVER_OPTS="$HBASE_REGIONSERVER_OPTS $HBASE_JMX_BASE -Dcom.sun.management.jmxremote.port={{ .HBASE_REGIONSERVER_JMX_PORT }} -Dcom.sun.management.jmxremote.rmi.port={{ .HBASE_REGIONSERVER_JMX_PORT }} -Dhbase.regionserver.hostname=${POD_FQDN:-$(hostname -f 2>/dev/null || hostname)} -Xms{{ .HBASE_REGIONSERVER_HEAP_SIZE }} -Xmx{{ .HBASE_REGIONSERVER_HEAP_SIZE }}"
export HBASE_HEAPSIZE={{ .HBASE_HEAP_SIZE }}

export HBASE_DISABLE_HADOOP_CLASSPATH_LOOKUP=true
export LD_LIBRARY_PATH={{ .HADOOP_NATIVE_LIB_PATH }}:${LD_LIBRARY_PATH:-}
