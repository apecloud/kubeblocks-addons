#!/bin/bash
set -ox pipefail
source /scripts/common.sh

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
		ch_query "${KB_JOIN_MEMBER_POD_FQDN}" "$create_query;"
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
		ch_query "${KB_JOIN_MEMBER_POD_FQDN}" "$query;"
		if [[ $? -eq 253 ]]; then
			echo "Replicas already exists, will drop the replica"
			ch_query "$pod_fqdn" "SYSTEM DROP REPLICA '${KB_JOIN_MEMBER_POD_NAME}' FROM TABLE ${database}.${table}"
			ch_query "${KB_JOIN_MEMBER_POD_FQDN}" "$query;"
		fi
	done
}

if server_is_ok "${KB_JOIN_MEMBER_POD_FQDN}"; then
	echo "Server ${KB_JOIN_MEMBER_POD_NAME} is OK"
else
	echo "Server ${KB_JOIN_MEMBER_POD_NAME} is not OK"
	exit 1
fi

for pod_fqdn in $(echo "$CLICKHOUSE_POD_FQDN_LIST" | tr ',' '\n'); do
	pod_fqdn=${pod_fqdn%:*}
	if [ "$pod_fqdn" == "${KB_JOIN_MEMBER_POD_NAME}*" ]; then
		echo "Skipping new member pod: $pod_fqdn"
		continue
	fi
	if server_is_ok "$pod_fqdn"; then
		echo "Server $pod_fqdn is OK"
	else
		echo "Server $pod_fqdn is not OK, skipping..."
		continue
	fi
	create_databases "$pod_fqdn"
	create_tables "$pod_fqdn"
	break
done
