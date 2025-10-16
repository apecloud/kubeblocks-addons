{{- $phy_memory := getContainerMemory ( index $.podSpec.containers 0 ) }}
be_port=9060
heartbeat_service_port=9050
webserver_port=8040
brpc_port=8060
sys_log_level=INFO

{{- if le $phy_memory 2147483648 }}
JAVA_OPTS="-Xmx1024m -Xloggc:/opt/apache-doris/log/be.gc.log.${CUR_DATE} -Dsun.java.command=DorisBE -XX:-CriticalJNINatives"
{{- else if le $phy_memory 8589934592 }}
JAVA_OPTS="-Xmx2048m -Xloggc:/opt/apache-doris/log/be.gc.log.${CUR_DATE} -Dsun.java.command=DorisBE -XX:-CriticalJNINatives"
{{- else }}
JAVA_OPTS="-Xmx4096m -Xloggc:/opt/apache-doris/log/be.gc.log.${CUR_DATE} -Dsun.java.command=DorisBE -XX:-CriticalJNINatives"
{{- end}}

