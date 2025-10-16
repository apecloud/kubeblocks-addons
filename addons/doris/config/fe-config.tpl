
{{- $phy_memory := getContainerMemory ( index $.podSpec.containers 0 ) }}
{{- $heap_size := mul (div $phy_memory 10) 8 }}

JAVA_OPTS="-Xmx{{ $heap_size }} -XX:+UseMembar -XX:SurvivorRatio=8 -XX:MaxTenuringThreshold=7 -XX:+PrintGCDateStamps -XX:+PrintGCDetails -XX:+UseConcMarkSweepGC -XX:+UseParNewGC -XX:+CMSClassUnloadingEnabled -XX:-CMSParallelRemarkEnabled -XX:CMSInitiatingOccupancyFraction=80 -XX:SoftRefLRUPolicyMSPerMB=0 -Xloggc:/opt/apache-doris/fe/log/fe.gc.log.$DATE"

lower_case_table_names=1
enable_fqdn_mode=true