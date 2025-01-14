binlog_checksum=NONE
plugin_load_add='group_replication.so'
group_replication_group_name= {{ .CLUSTER_UUID }}
group_replication_start_on_boot=off
#group_replication_local_address= "s1:33061"
#group_replication_group_seeds= "s1:33061,s2:33061,s3:33061"
group_replication_bootstrap_group=off