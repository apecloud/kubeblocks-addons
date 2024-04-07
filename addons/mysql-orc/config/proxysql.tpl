{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}

{{- $mysql_component := fromJson "{}" }}
{{- range $i, $e := $.cluster.spec.componentSpecs }}
  {{- if index $e "componentDef" }}
    {{- if eq $e.componentDef "mysql" }}
      {{- $mysql_component = $e }}
    {{- end }}
  {{- end }}
{{- end }}
{{- $mysql_replicas := $mysql_component.replicas | int }}

{{- $proxysql_component := fromJson "{}" }}
{{- range $i, $e := $.cluster.spec.componentSpecs }}
  {{- if index $e "componentDef" }}
    {{- if eq $e.componentDef "proxysql" }}
      {{- $proxysql_component = $e }}
    {{- end }}
  {{- end }}
{{- end }}
{{- $proxy_replicas := $proxysql_component.replicas | int }}


datadir="/var/lib/proxysql"
admin_variables=
{
	refresh_interval="2000"
	cluster_proxysql_servers_save_to_disk="true"
	cluster_mysql_servers_diffs_before_sync="3"
	cluster_password="nb2wZpZ9OXXTF2Mv"
	mysql_ifaces="0.0.0.0:6032"
	cluster_check_status_frequency="100"
	cluster_mysql_users_diffs_before_sync="3"
	cluster_proxysql_servers_diffs_before_sync="3"
	admin_credentials="admin:admin;cluster:nb2wZpZ9OXXTF2Mv"
	admin-hash_passwords="true"
	cluster_check_interval_ms="200"
	cluster_mysql_servers_save_to_disk="true"
	cluster_mysql_users_save_to_disk="true"
	cluster_mysql_query_rules_diffs_before_sync="3"
	cluster_mysql_query_rules_save_to_disk="true"
	cluster_username="cluster"
}
mysql_variables=
{
	threads="4"
	monitor_password="proxysql"
	poll_timeout="2000"
	ssl_p2s_cert="/var/lib/certs/tls.crt"
	server_version="8.0.27"
	ssl_p2s_ca="/var/lib/certs/ca.crt"
	ssl_p2s_key="/var/lib/certs/tls.key"
	monitor_connect_interval="200000"
	monitor_username="proxysql"
	have_compress="true"
	monitor_galera_healthcheck_interval="2000"
	stacksize="1048576"
	ping_timeout_server="200"
	monitor_galera_healthcheck_timeout="800"
	max_connections="2048"
	monitor_ping_interval="200000"
	monitor_history="60000"
	commands_stats="true"
	default_query_delay="0"
	have_ssl="false"
	default_schema="information_schema"
	ping_interval_server_msec="10000"
	default_query_timeout="36000000"
	connect_timeout_server="10000"
	sessions_sort="true"
	interfaces="0.0.0.0:6033;/tmp/proxysql.sock"
}
mysql_users=
(
)
mysql_query_rules=
(
	{
		re_modifiers="CASELESS"
		flagIN=0
		apply=1
		rule_id=1
		destination_hostgroup=2
		match_digest="^SELECT.*FOR UPDATE$"
		negate_match_pattern=0
		active=1
	},
	{
		apply=1
		active=1
		re_modifiers="CASELESS"
		negate_match_pattern=0
		destination_hostgroup=3
		flagIN=0
		match_digest="^SELECT"
		rule_id=2
	},
	{
		re_modifiers="CASELESS"
		destination_hostgroup=2
		active=1
		rule_id=3
		match_digest=".*"
		apply=1
		negate_match_pattern=0
		flagIN=0
	}
)
mysql_group_replication_hostgroups=
(
	{
		writer_hostgroup = 2
		backup_writer_hostgroup = 4
		reader_hostgroup = 3
		offline_hostgroup = 1
		active = 1
		max_writers = 1
		writer_is_also_reader = 1
		max_transactions_behind = 0
	}
)

proxysql_servers=
(
{{- range $i, $e := until $proxy_replicas }}
  {{- $service_host := printf "%s-%s-proxy-ordinal-%d.%s" $clusterName $proxysql_component.name $i $namespace }}
  {{- if eq $i (sub $proxy_replicas 1) }}
    { hostname = "{{$service_host}}", port = 6032, weight = 1 }
  {{- else }}
    { hostname = "{{$service_host}}", port = 6032, weight = 1 },
  {{- end }}
{{- end }}
)

mysql_servers=
(
{{- range $i, $e := until $mysql_replicas }}
  {{- $mysql_service_host := printf "%s-%s-mysql-%d.%s" $clusterName $mysql_component.name $i $namespace }}

  {{- $hostgroup_id := 3 }}
  {{- if eq $i 0 }}
    {{- $hostgroup_id = 2 }}
  {{- end }}
  {{- if eq $i (sub $mysql_replicas 1) }}
    { hostgroup_id = {{$hostgroup_id}} , hostname = "{{$mysql_service_host}}", port = 3306, weight = 1, use_ssl = 0 }
  {{- else }}
    { hostgroup_id = {{$hostgroup_id}} , hostname = "{{$mysql_service_host}}", port = 3306, weight = 1, use_ssl = 0 },
  {{- end }}
{{- end }}
)