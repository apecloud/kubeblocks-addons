#!/bin/bash

function restore_sentinel_acl() {
  export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
  export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

  if [ -z "$SENTINEL_POD_FQDN_LIST" ]; then
     echo "INFO: no sentinel found, skip restore sentinel ACL file"
     return
  fi

  sentinel_acl_file="sentinel.acl"
  if [ "$(datasafed list $sentinel_acl_file)" == "${sentinel_acl_file}" ]; then
    datasafed pull "${sentinel_acl_file}" /tmp/sentinel.acl
  fi

  for sentinel_fqdn in $(echo "$SENTINEL_POD_FQDN_LIST" | tr "," "\n"); do
      echo "INFO: restore sentinel ${sentinel_fqdn} ACL file"
      sentinel_cmd="redis-cli $REDIS_CLI_TLS_CMD -h $sentinel_fqdn -p ${SENTINEL_SERVICE_PORT}"
      if [ -n "$SENTINEL_PASSWORD" ]; then
          sentinel_cmd="$sentinel_cmd -a $SENTINEL_PASSWORD"
      fi
      if [ "$($sentinel_cmd ping)" != "PONG" ]; then
          echo "Waring: failed to connect sentinel ${sentinel_fqdn}, skip"
          continue
      fi
      while IFS= read -r user_rule; do
          [[ -z "$user_rule" ]] && continue

          if [[ "$user_rule" =~ ^user[[:space:]]+([^[:space:]]+) ]]; then
              username="${BASH_REMATCH[1]}"
          else
            # skip invalid user rule
            continue
          fi

          if [[ "$username" == "default" ]]; then
              continue
          fi
          rule_part="${user_rule#user $username }"
          echo "$username" $rule_part
          $sentinel_cmd ACL SETUSER "$username" $rule_part >&2
      done < /tmp/sentinel.acl
      break
  done
}
# restore sentinel acl
restore_sentinel_acl
if [ -z "$DP_RESTORE_KEY_PATTERNS" ]; then
    echo "DP_RESTORE_KEY_PATTERNS is not set. Exiting..."
    exit 0
fi

# lua script to migrate keys from local redis instance to the cluster to be restored.
LUA_SCRIPT=$(cat <<'EOF'
local pattern = ARGV[1]
local destination_host = ARGV[2]
local destination_port = ARGV[3]
local db = tonumber(ARGV[4])
local destination_username= ARGV[5]
local destination_password= ARGV[6]

local cursor = "0"
local batch_size = 300
local timeout = 5000
local retry_limit = 3

local function migrate_key(key)
    local attempt = 0
    local success = false

    while attempt < retry_limit and not success do
        attempt = attempt + 1
        local ok, err = pcall(function()
            redis.call("MIGRATE", destination_host, destination_port, key, db, timeout, "AUTH2", destination_username, destination_password)
        end)

        if ok then
            success = true
        end
    end

    if not success then
        return "Migration failed for key " .. key
    end
    return nil
end

local migration_failed = false
redis.call("SELECT", db)
-- scan keys with pattern and migrate them to destination redis instance
repeat
    local scan_result = redis.call("SCAN", cursor, "MATCH", pattern, "COUNT", batch_size)
    cursor = scan_result[1]
    local keys = scan_result[2]

    for i, key in ipairs(keys) do
        local result = migrate_key(key)
        if result then
            migration_failed = true
        end
    end
until cursor == "0"

if migration_failed then
    return "Migration completed with errors for database: " .. db .. " and pattern: " .. pattern
else
    return "Migration completed successfully for database: " .. db .. " and pattern: " .. pattern
end

EOF
)

# start local redis instance
LOCAL_DATA_DIR="${DATA_DIR}/.restore_keys"
redis-stack-server --dir "$LOCAL_DATA_DIR"  --appendonly "yes" &
while ! redis-cli ping | grep -q "PONG"; do
    echo "Waiting for Redis to start..."
    sleep 1
done

# use comma  as delimiter to split patterns
IFS=',' read -r -a patterns_array <<< "$DP_RESTORE_KEY_PATTERNS"
DB_COUNT=$(redis-cli -h ${DP_DB_HOST} -p ${DP_DB_PORT} -a ${REDIS_DEFAULT_PASSWORD} CONFIG GET databases | awk 'NR==2')
pids=()

echo "start migration for all databases and patterns..."
# migrate keys for each database and pattern in parallel
for db in $(seq 0 $((DB_COUNT - 1))); do
    for pattern in "${patterns_array[@]}"; do
        (
            #echo "Migrating pattern '$pattern' from database '$db'"
            output=$(redis-cli  --eval <(echo "$LUA_SCRIPT") , "$pattern" "$DP_DB_HOST" "$DP_DB_PORT" "$db" "$REDIS_DEFAULT_USER" "$REDIS_DEFAULT_PASSWORD")
            echo "$output"
            # Check the output for errors
            if [[ "$output" == *"errors"* ]] && [[ "$DP_RESTORE_KEY_IGNORE_ERRORS" != "true" ]]; then
                exit 1
            fi
        ) &
        pids+=($!)
    done
done

for pid in "${pids[@]}"; do
    wait $pid
    if [ $? -ne 0 ]; then
        echo "A migration process failed. Exiting..."
        exit 1
    fi
done

# as the MIGRATE command transform data in binary format, which will corrupt aof file, we need to trigger BGREWRITEAOF after migration.
redis-cli -h ${DP_DB_HOST} -p ${DP_DB_PORT} -a ${REDIS_DEFAULT_PASSWORD} BGREWRITEAOF
mv "${LOCAL_DATA_DIR}/users.acl" "$DATA_DIR"
rm -rf "$LOCAL_DATA_DIR"
echo "Migration completed for all databases and patterns!"
