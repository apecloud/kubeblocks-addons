#!/bin/bash

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
        else
            redis.log(redis.LOG_WARNING, "Migration failed for key " .. key .. " on attempt " .. attempt .. ": " .. err)
        end
    end

    if not success then
        redis.log(redis.LOG_ERR, "Migration failed for key " .. key .. " after " .. retry_limit .. " attempts")
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
        local result = migrate_key(key, db)
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
            redis-cli  --eval <(echo "$LUA_SCRIPT") , "$pattern" "$DP_DB_HOST" "$DP_DB_PORT" "$db" "$REDIS_DEFAULT_USER" "$REDIS_DEFAULT_PASSWORD"
        ) &
        pids+=($!)
    done
done

for pid in "${pids[@]}"; do
    wait $pid
done

# as the MIGRATE command transform data in binary format, which will corrupt aof file, we need to trigger BGREWRITEAOF after migration.
redis-cli -h ${DP_DB_HOST} -p ${DP_DB_PORT} -a ${REDIS_DEFAULT_PASSWORD} BGREWRITEAOF
mv "${LOCAL_DATA_DIR}/users.acl" "$DATA_DIR"
rm -rf "$LOCAL_DATA_DIR"
echo "Migration completed for all databases and patterns!"
