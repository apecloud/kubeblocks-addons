declare -a new_shard_pod_fqdns=()
declare -a old_shard_available_pod_fqdns=()
declare -a create_meta_failed_pods=()

function log() {
    echo "[$(date)] $@"
}

function execute_sql() {
  local pod_fqdn="$1"
  local query="$2"
  clickhouse-client --user ${CLICKHOUSE_ADMIN_USER} --password ${CLICKHOUSE_ADMIN_PASSWORD} --host="$pod_fqdn" \
    --connect_timeout=2 \
    --query="${query}"
}

function server_is_ok() {
  local pod_fqdn="$1"
  for i in {1..30}; do
    sleep 1
    execute_sql "$pod_fqdn" "select 1"
    if [[ $? -eq 0 ]]; then
        return 0
    fi
  done
  return $?
}

function get_new_shard_and_old_available_pod_fqdns() {
   declare -A pods_map
   current_component=""
   OLD_IFS=$IFS
   IFS=',' read -ra entries <<< "$ALL_COMBINED_SHARDS_POD_FQDN_LIST"
   for entry in "${entries[@]}"; do
       if [[ "$entry" == *":"* ]]; then
           IFS=':' read -r component pod <<< "$entry"
           current_component="$component"
           pods_map["$component"]="$pod"
       else
           pods_map["$current_component"]+=",$entry"
       fi
   done
   for component in "${!pods_map[@]}"; do
      shard_pod_fqdn_list=${pods_map[$component]}
      declare -a current_shard_pod_fqdns=()
      is_old_shard=false
      for pod_fqdn in $(echo $shard_pod_fqdn_list | tr ',' ' '); do
          tableCount=$(execute_sql "$pod_fqdn" "SELECT count(name) FROM system.tables WHERE database NOT IN ('system', 'INFORMATION_SCHEMA','information_schema')")
          if [[ $tableCount -gt 0 ]]; then
            # 获得最多5个原shard的pod fqdn
            if [[ ${#old_shard_available_pods[@]} -lt 5 ]]; then
               old_shard_available_pod_fqdns+=("$pod_fqdn")
            fi
            is_old_shard=true
            break
          else
            current_shard_pod_fqdns+=("$pod_fqdn")
          fi
      done
      if [[ "$is_old_shard" == "false" ]]; then
          new_shard_pod_fqdns+=("${current_shard_pod_fqdns[@]}")
      fi
   done
   IFS=$OLD_IFS
}


function create_databases() {
   pod_fqdn="$1"
   new_pod_fqdn="$2"
   log "Creating databases..."
   execute_sql "$pod_fqdn" "select name from system.databases WHERE name NOT IN ('system', 'INFORMATION_SCHEMA','information_schema')" | while read -r db; do
       create_query=$(execute_sql "${pod_fqdn}" "SHOW CREATE DATABASE ${db} FORMAT TabSeparatedRaw")
       log "create database sql: $create_query"
       execute_sql "${new_pod_fqdn}" "$create_query;"
       databaseCount=$(execute_sql "${new_pod_fqdn}" "SELECT count(name) FROM system.databases WHERE name='${db}'")
       if [[ ${databaseCount} -ne 1 ]]; then
         log "Database ${db} create failed, please retry this operation"
         exit 1
       fi
   done
   return $?
}

function create_tables() {
   pod_fqdn="$1"
   new_pod_fqdn="$2"
   log "Creating tables..."
   execute_sql "${pod_fqdn}" "SELECT database,name, uuid FROM system.tables WHERE database NOT IN ('system', 'INFORMATION_SCHEMA','information_schema') order by dependencies_table desc" | while read -a row; do
     database=${row[0]}
     table=${row[1]}
     uuid=${row[2]}
     if [[ "$table" == *".inner_id."* ]] || [[ "$table" == *".inner."* ]]; then
        log "Skip inner table: $table"
        continue
     fi
     query=$(execute_sql "${pod_fqdn}" "SHOW CREATE TABLE ${database}.${table} FORMAT TabSeparatedRaw")
     if [[ "$query" == *"CREATE MATERIALIZED VIEW"* ]]; then
        inner_uuid=$(execute_sql "${pod_fqdn}" "SELECT uuid FROM system.tables WHERE database = '${database}' AND name = '.inner_id.${uuid}'")
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
     log "create table sql: $query"
     execute_sql "${new_pod_fqdn}" "$query;"
     if [[ $? -eq 253 ]]; then
       log "Replicas already exists, will drop the replica"
       drop_replica_sql="SYSTEM DROP REPLICA '${new_pod_fqdn%%.*}' FROM TABLE ${database}.${table}"
       log "drop replica sql: $drop_replica_sql"
       execute_sql "${pod_fqdn}" "${drop_replica_sql}"
       execute_sql "${new_pod_fqdn}" "$query;"
     fi
     tableCount=$(execute_sql "${new_pod_fqdn}" "SELECT count(name) FROM system.tables WHERE database='${database}' and name='${table}'")
     if [[ $tableCount -ne 1 ]]; then
       log "Table ${database}.${table} create failed, please retry this operation"
       exit 1
     fi
   done
   return $?
}

function get_available_pod_fqdn() {
  for pod_fqdn in "${old_shard_available_pod_fqdns[@]}"; do
     execute_sql "$pod_fqdn" "select 1" 2>&1 > /dev/null
     if [[ $? -eq 0 ]]; then
       echo "$pod_fqdn"
       break
     fi
  done
}

# 1. get new shard pods and the old available pod fqdns
get_new_shard_and_old_available_pod_fqdns
log "new_shard_pods: ${new_shard_pod_fqdns[@]}"
log "old_shard_available_pods: ${old_shard_available_pod_fqdns[@]}"

if [[ ${#old_shard_available_pod_fqdns[@]} -eq 0 ]]; then
    log "info: No tables found in old shard, no need to create databases and tables for new shard pods.
         You can create the databases and tables manually if needed."
    exit 0
fi

# 2. create databases and tables for new shard pods
for new_shard_pod_fqdn in "${new_shard_pod_fqdns[@]}"; do
    old_available_pod_fqdn=$(get_available_pod_fqdn)
    new_shard_pod_name=${new_shard_pod_fqdn%%.*}
    if [[ -z "$old_available_pod_fqdn" ]]; then
        log "ERROR: No available pod found in old shard for pod $new_shard_pod_name"
        create_meta_failed_pods+=("$new_shard_pod_name")
        continue
    fi
    if server_is_ok "$new_shard_pod_fqdn"; then
        log "Server $new_shard_pod_name is OK, old available pod fqdn: $old_available_pod_fqdn"
    else
        log "Server $new_shard_pod_name is not OK, skipping..."
        create_meta_failed_pods+=("$new_shard_pod_name")
        continue
    fi
    create_databases "$old_available_pod_fqdn" "$new_shard_pod_fqdn"
    if [[ $? -ne 0 ]]; then
       log "ERROR: Database create failed for pod $new_shard_pod_name, please retry this operation"
       create_meta_failed_pods+=("$new_shard_pod_name")
       continue
    fi
    create_tables "$old_available_pod_fqdn" "$new_shard_pod_fqdn"
    if [[ $? -ne 0 ]]; then
      log "ERROR: Table create failed for pod $new_shard_pod_name, please retry this operation"
      create_meta_failed_pods+=("$new_shard_pod_name")
      continue
    fi
done

if [[ ${#create_meta_failed_pods[@]} -gt 0 ]]; then
    log "ERROR: Failed to create metadata for pods: ${create_meta_failed_pods[@]}, you can to create the databases and tables manually"
    exit 1
fi
