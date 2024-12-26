spark.eventLog.enabled            true
spark.eventLog.dir                hdfs://k8scluster:8020/spark-history
spark.history.fs.logDirectory     hdfs://k8scluster:8020/spark-history
spark.yarn.historyServer.address  localhost:18080
spark.history.ui.port             18080