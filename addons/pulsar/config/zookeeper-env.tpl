PULSAR_GC: -XX:+UseG1GC -XX:MaxGCPauseMillis=10 -Dcom.sun.management.jmxremote -Djute.maxbuffer=10485760 -XX:+ParallelRefProcEnabled -XX:+UnlockExperimentalVMOptions -XX:+DoEscapeAnalysis -XX:+DisableExplicitGC -XX:+ExitOnOutOfMemoryError -XX:+PerfDisableSharedMem -XX:ActiveProcessorCount=1
PULSAR_MEM: -XX:MinRAMPercentage=40 -XX:MaxRAMPercentage=60
PULSAR_PREFIX_serverCnxnFactory: org.apache.zookeeper.server.NIOServerCnxnFactory
dataDir: /pulsar/data/zookeeper
serverCnxnFactory: org.apache.zookeeper.server.NIOServerCnxnFactory
