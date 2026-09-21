#!/bin/bash
# restore-keys.sh — postReady phase (redis-aligned).
#
# Two jobs, in order of importance:
#   1. Restore the Sentinel ACL rules captured by the backup into every
#      reachable Sentinel pod (no-op unless SENTINEL_POD_FQDN_LIST /
#      SENTINEL_PASSWORD are supplied via the restore env — the BackupPolicy
#      env schema cannot inject cross-component credentials, same as redis).
#   2. When DP_RESTORE_KEY_PATTERNS is set (partial restore): prepareData has
#      staged the full archive under ${DATA_DIR}/.restore_keys.  Start a local
#      Valkey on that directory, SCAN each pattern and MIGRATE the matching
#      keys into the freshly restored (empty) target cluster, then BGREWRITEAOF
#      (MIGRATE ships binary data that would corrupt the AOF otherwise).
#
# KubeBlocks DataProtection injects:
#   DP_DB_HOST / DP_DB_PORT / DP_DB_USER / DP_DB_PASSWORD — restored target
#   DP_RESTORE_KEY_PATTERNS — comma-separated key patterns (optional)
#   DATA_DIR — data mount path (set in ActionSet env)

set -e
set -o pipefail

if [ -n "${DP_DATASAFED_BIN_PATH}" ]; then export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"; fi

# TLS args for the TARGET cluster: the job does not mount the TLS volume, so
# TLS args — redis addon parity: when the ComponentDefinition's TLS_ENABLED
# (tlsVarRef) reaches this execution face it is the ONLY switch, and it maps to
# the same `--tls --insecure` the redis addon uses for its cli vars.
# Certificate verification is impossible there: no CA file is available in this execution face (in-cluster CLIs verify via --cacert).
# Backup/restore jobs are not guaranteed to receive component vars, so when
# TLS_ENABLED is absent fall back to a connection probe (plain, then
# --tls --insecure).
_tls_args=()
if [ "${TLS_ENABLED:-}" = "true" ]; then
  _tls_args=(--tls --insecure)
  echo "INFO: TLS_ENABLED=true — using --tls --insecure"
elif [ -z "${TLS_ENABLED:-}" ]; then
  _probe_base=(valkey-cli --no-auth-warning -h "${DP_DB_HOST}" -p "${DP_DB_PORT}")
  if [ -n "${DP_DB_PASSWORD:-}" ]; then
    _probe_base+=(-a "${DP_DB_PASSWORD}")
  fi
  if ! "${_probe_base[@]}" PING 2>/dev/null | grep -q "PONG"; then
    if "${_probe_base[@]}" --tls --insecure PING 2>/dev/null | grep -q "PONG"; then
      _tls_args=(--tls --insecure)
      echo "INFO: TLS detected via connection probe — using --tls --insecure"
    fi
  fi
fi

target_cli=(valkey-cli --no-auth-warning "${_tls_args[@]}" -h "${DP_DB_HOST}" -p "${DP_DB_PORT}")
if [ -n "${DP_DB_PASSWORD:-}" ]; then
  target_cli+=(-a "${DP_DB_PASSWORD}")
fi

function restore_sentinel_acl() {
  if [ -z "${SENTINEL_POD_FQDN_LIST}" ]; then
    echo "INFO: no sentinel found, skip restore sentinel ACL file"
    return 0
  fi
  [ -n "${DP_DATASAFED_BIN_PATH}" ] || return 0
  export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH}"

  local sentinel_acl_file="sentinel.acl"
  if [ "$(datasafed list "${sentinel_acl_file}" 2>/dev/null)" != "${sentinel_acl_file}" ]; then
    echo "INFO: no ${sentinel_acl_file} in the backup repository, skip"
    return 0
  fi
  datasafed pull "${sentinel_acl_file}" /tmp/sentinel.acl

  local sentinel_fqdn s_cli
  for sentinel_fqdn in $(echo "${SENTINEL_POD_FQDN_LIST}" | tr ',' '\n'); do
    echo "INFO: restore sentinel ${sentinel_fqdn} ACL file"
    s_cli=(valkey-cli --no-auth-warning -h "${sentinel_fqdn}" -p "${SENTINEL_SERVICE_PORT:-26379}")
    [ -n "${SENTINEL_PASSWORD:-}" ] && s_cli+=(-a "${SENTINEL_PASSWORD}")
    if ! "${s_cli[@]}" PING 2>/dev/null | grep -q "PONG"; then
      echo "WARNING: failed to connect sentinel ${sentinel_fqdn}, skip"
      continue
    fi
    local user_rule username rule_part
    while IFS= read -r user_rule; do
      [ -z "${user_rule}" ] && continue
      if [[ "${user_rule}" =~ ^user[[:space:]]+([^[:space:]]+) ]]; then
        username="${BASH_REMATCH[1]}"
      else
        continue
      fi
      [ "${username}" = "default" ] && continue
      rule_part="${user_rule#user ${username} }"
      echo "${username} ${rule_part}"
      "${s_cli[@]}" ACL SETUSER "${username}" ${rule_part} >&2
    done < /tmp/sentinel.acl
    break
  done
}

# restore sentinel ACL
restore_sentinel_acl

if [ -z "${DP_RESTORE_KEY_PATTERNS}" ]; then
  echo "DP_RESTORE_KEY_PATTERNS is not set. Exiting..."
  exit 0
fi

# lua script to migrate keys from the local valkey instance (staging the full
# backup archive) to the cluster being restored.
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
-- scan keys with pattern and migrate them to destination valkey instance
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

# start the local valkey instance on the staged backup directory.
LOCAL_DATA_DIR="${DATA_DIR}/.restore_keys"
valkey-server --port 6379 --dir "${LOCAL_DATA_DIR}" --appendonly yes &
while ! valkey-cli --no-auth-warning -h 127.0.0.1 -p 6379 ping 2>/dev/null | grep -q "PONG"; do
  echo "Waiting for Valkey to start..."
  sleep 1
done

# use comma as delimiter to split patterns
IFS=',' read -r -a patterns_array <<< "${DP_RESTORE_KEY_PATTERNS}"
target_username="${DP_DB_USER:-default}"
target_password="${DP_DB_PASSWORD:-}"
DB_COUNT=$("${target_cli[@]}" CONFIG GET databases | awk 'NR==2')
pids=()

echo "start migration for all databases and patterns..."
# migrate keys for each database and pattern in parallel
for db in $(seq 0 $((DB_COUNT - 1))); do
  for pattern in "${patterns_array[@]}"; do
    (
      output=$(valkey-cli --no-auth-warning --eval <(echo "${LUA_SCRIPT}") , "${pattern}" "${DP_DB_HOST}" "${DP_DB_PORT}" "${db}" "${target_username}" "${target_password}")
      echo "${output}"
      if [[ "${output}" == *"errors"* ]] && [[ "${DP_RESTORE_KEY_IGNORE_ERRORS}" != "true" ]]; then
        exit 1
      fi
    ) &
    pids+=($!)
  done
done

for pid in "${pids[@]}"; do
  wait "${pid}"
  if [ $? -ne 0 ]; then
    echo "A migration process failed. Exiting..."
    exit 1
  fi
done

# as the MIGRATE command transforms data in binary format, which will corrupt
# the aof file, we need to trigger BGREWRITEAOF after migration.
"${target_cli[@]}" BGREWRITEAOF
if [ -f "${LOCAL_DATA_DIR}/users.acl" ]; then
  mv "${LOCAL_DATA_DIR}/users.acl" "${DATA_DIR}"
fi
rm -rf "${LOCAL_DATA_DIR}"
echo "Migration completed for all databases and patterns!"
