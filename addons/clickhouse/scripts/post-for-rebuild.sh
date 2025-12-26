#!/bin/bash
source /scripts/common.sh

component_name=${instanceName%-*}
instance_fqdn=${instanceName}.${component_name}-headless

function server_is_ok() {
	local pod_fqdn="$1"
	ch_query "$pod_fqdn" "show databases"
	return $?
}

function create_databases() {
	pod_fqdn="$1"
	echo "Creating databases..."
	ch_query "$pod_fqdn" "select name from system.databases WHERE name NOT IN ('system', 'INFORMATION_SCHEMA','information_schema')" | while read -r db; do
		create_query=$(ch_query "$pod_fqdn" "SHOW CREATE DATABASE ${db} FORMAT TabSeparatedRaw")
		echo "create database sql: $create_query"
		ch_query "${instance_fqdn}" "$create_query;"
		databaseCount=$(ch_query "${instance_fqdn}" "SELECT count(name) FROM system.databases WHERE name='${db}'")
		if [[ ${databaseCount} -ne 1 ]]; then
			echo "Database ${db} create failed, please retry this operation"
			exit 1
		fi
	done
}

function create_tables() {
	pod_fqdn="$1"
	echo "Creating tables..."
	ch_query "$pod_fqdn" "SELECT database,name, uuid FROM system.tables WHERE database NOT IN ('system', 'INFORMATION_SCHEMA','information_schema') order by dependencies_table desc" | while read -a row; do
		database=${row[0]}
		table=${row[1]}
		uuid=${row[2]}
		if [[ "$table" == *".inner_id."* ]] || [[ "$table" == *".inner."* ]]; then
			echo "Skip inner table: $table"
			continue
		fi
		query=$(ch_query "$pod_fqdn" "SHOW CREATE TABLE ${database}.${table} FORMAT TabSeparatedRaw")
		if [[ "$query" == *"CREATE MATERIALIZED VIEW"* ]]; then
			inner_uuid=$(ch_query "$pod_fqdn" "SELECT uuid FROM system.tables WHERE database = '${database}' AND name = '.inner_id.${uuid}'")
			query=$(echo "$query" | sed "s/MATERIALIZED VIEW ${database}.${table}/MATERIALIZED VIEW ${database}.${table} UUID '${uuid}' TO INNER UUID '${inner_uuid}'/")
		elif [[ "$query" == *"CREATE LIVE VIEW"* ]]; then
			query="SET allow_experimental_live_view = 1;${query};"
		elif [[ "$query" == *"CREATE WINDOW VIEW"* ]]; then
			query=$(echo "$query" | sed "s/WINDOW VIEW ${database}.${table}/WINDOW VIEW ${database}.${table} UUID '${uuid}'/")
			query="SET allow_experimental_window_view = 1;set allow_experimental_analyzer=0;${query};"
		elif [[ "$query" == *"{uuid}"* ]]; then
			# https://github.com/ClickHouse/ClickHouse/pull/59908
			# replace CREATE TABLE database.table to CREATE TABLE database.table UUID 'uuid'
			# for older version: replace uuid
			query=$(echo "$query" | sed "s/{uuid}/${uuid}/")
		fi
		echo "create table sql: $query"
		ch_query "${instance_fqdn}" "$query;"
		if [[ $? -eq 253 ]]; then
			echo "Replicas already exists, will drop the replica"
			drop_replica_sql="SYSTEM DROP REPLICA '${instanceName}' FROM TABLE ${database}.${table}"
			echo "drop replica sql: $drop_replica_sql"
			ch_query "$pod_fqdn" "${drop_replica_sql}"
			ch_query "${instance_fqdn}" "$query;"
		fi
		tableCount=$(ch_query "${instance_fqdn}" "SELECT count(name) FROM system.tables WHERE database='${database}' and name='${table}'")
		if [[ $tableCount -ne 1 ]]; then
			echo "Table ${database}.${table} create failed, please retry this operation"
			exit 1
		fi
	done
}

function wait_instance_serviceable() {
	while true; do
		ch_query "$instance_fqdn" "show databases"
		if [[ $? -eq 0 ]]; then
			echo "Server $instance_fqdn is OK"
			break
		fi
		echo "Server $instance_fqdn is not OK, waiting..."
		sleep 1
	done
}

if [[ $CLICKHOUSE_COMP_REPLICAS -eq 1 ]]; then
	echo "You need to rebuild instance by backup"
	exit 1
fi

# wait for endpoint is ok
# sleep 10
wait_instance_serviceable

for ((i = 0; i < $CLICKHOUSE_COMP_REPLICAS; i++)); do
	pod_name="${component_name}-${i}"
	if [[ "${pod_name}" == ${instanceName} ]]; then
		echo "Skip the rebuild instance: ${instanceName}"
		continue
	fi
	pod_fqdn=${pod_name}.${component_name}-headless
	if server_is_ok "$pod_fqdn"; then
		echo "Server $pod_fqdn is OK"
	else
		echo "Server $pod_fqdn is not OK, skipping..."
		continue
	fi
	create_databases "$pod_fqdn"
	if [[ $? -ne 0 ]]; then
		echo "Database create failed, please retry this operation"
		exit 1
	fi
	create_tables "$pod_fqdn"
	if [[ $? -ne 0 ]]; then
		echo "Table create failed, please retry this operation"
		exit 1
	fi
	break
done
