#!/usr/bin/env bash
set -euo pipefail

: "${HBASE_HOME:=/opt/hbase}"

REGIONSERVER_HOST="${KB_LEAVE_MEMBER_POD_FQDN:-${KB_LEAVE_MEMBER_POD_NAME:-}}"
REGIONSERVER_PORT="${HBASE_REGIONSERVER_PORT:-16020}"
REGIONMOVER_TIMEOUT_SECONDS="${REGIONMOVER_TIMEOUT_SECONDS:-300}"
if [[ -z "${REGIONSERVER_HOST}" ]]; then
  echo "KB_LEAVE_MEMBER_POD_FQDN or KB_LEAVE_MEMBER_POD_NAME is required" >&2
  exit 1
fi

REGIONSERVER_SERVER_NAME=""
SERVER_DECOMMISSIONED=false
REGIONMOVER_PID=""

# Runs a JRuby HBase admin script through the bundled HBase shell.
# Parameters:
#   $1: JRuby script content to execute.
# Returns:
#   0 when the script succeeds; non-zero otherwise.
hbase_admin_script() {
  local script_content="$1"
  printf '%s\n' "${script_content}" | "${HBASE_HOME}/bin/hbase" shell -n 2>/dev/null
}

# Resolves the live HBase ServerName for the leaving RegionServer.
# Parameters: none.
# Returns:
#   0 and prints the full ServerName when found; non-zero otherwise.
get_regionserver_server_name() {
  local output
  output="$(hbase_admin_script "$(cat <<EOF
java_import org.apache.hadoop.hbase.HBaseConfiguration
java_import org.apache.hadoop.hbase.client.ConnectionFactory

conn = nil
admin = nil
begin
  conn = ConnectionFactory.createConnection(HBaseConfiguration.create)
  admin = conn.getAdmin
  server = admin.getClusterMetrics.getLiveServerMetrics.keySet.find do |sn|
    sn.getHostname == '${REGIONSERVER_HOST}' && sn.getPort == ${REGIONSERVER_PORT}
  end
  raise 'regionserver not found' if server.nil?
  puts "KB_SERVER_NAME=#{server}"
ensure
  admin.close unless admin.nil?
  conn.close unless conn.nil?
end
EOF
)")" || return 1
  grep -Eo 'KB_SERVER_NAME=.*' <<< "${output}" | tail -n1 | cut -d= -f2-
}

# Marks the leaving RegionServer as decommissioned to block new assignments.
# Parameters:
#   $1: Full HBase ServerName for the leaving RegionServer.
# Returns:
#   0 when the server is decommissioned; non-zero otherwise.
decommission_regionserver() {
  local server_name="$1"
  hbase_admin_script "$(cat <<EOF
java_import org.apache.hadoop.hbase.HBaseConfiguration
java_import org.apache.hadoop.hbase.ServerName
java_import org.apache.hadoop.hbase.client.ConnectionFactory
java_import java.util.Collections

conn = nil
admin = nil
begin
  conn = ConnectionFactory.createConnection(HBaseConfiguration.create)
  admin = conn.getAdmin
  server = ServerName.parseServerName('${server_name}')
  admin.decommissionRegionServers(Collections.singletonList(server), false)
ensure
  admin.close unless admin.nil?
  conn.close unless conn.nil?
end
EOF
)"
}

# Removes the decommission marker so retries leave the server eligible again.
# Parameters:
#   $1: Full HBase ServerName for the leaving RegionServer.
# Returns:
#   0 when the server is recommissioned; non-zero otherwise.
recommission_regionserver() {
  local server_name="$1"
  hbase_admin_script "$(cat <<EOF
java_import org.apache.hadoop.hbase.HBaseConfiguration
java_import org.apache.hadoop.hbase.ServerName
java_import org.apache.hadoop.hbase.client.ConnectionFactory
java_import java.util.Collections

conn = nil
admin = nil
begin
  conn = ConnectionFactory.createConnection(HBaseConfiguration.create)
  admin = conn.getAdmin
  server = ServerName.parseServerName('${server_name}')
  admin.recommissionRegionServer(server, Collections.emptyList)
ensure
  admin.close unless admin.nil?
  conn.close unless conn.nil?
end
EOF
)"
}

# Reads the current region count hosted by the leaving RegionServer.
# Parameters:
#   $1: Full HBase ServerName for the leaving RegionServer.
# Returns:
#   0 and prints the region count when the query succeeds; non-zero otherwise.
get_regionserver_region_count() {
  local server_name="$1"
  local output
  output="$(hbase_admin_script "$(cat <<EOF
java_import org.apache.hadoop.hbase.HBaseConfiguration
java_import org.apache.hadoop.hbase.ServerName
java_import org.apache.hadoop.hbase.client.ConnectionFactory

conn = nil
admin = nil
begin
  conn = ConnectionFactory.createConnection(HBaseConfiguration.create)
  admin = conn.getAdmin
  server = ServerName.parseServerName('${server_name}')
  puts "KB_REGION_COUNT=#{admin.getRegions(server).size}"
ensure
  admin.close unless admin.nil?
  conn.close unless conn.nil?
end
EOF
)")" || return 1
  grep -Eo 'KB_REGION_COUNT=[0-9]+' <<< "${output}" | tail -n1 | cut -d= -f2
}

# Recommissions the server on failure so KubeBlocks retries do not leave it permanently drained.
# Parameters:
#   $1: The script exit code before cleanup.
# Returns:
#   Does not return; exits with the final status code.
cleanup_on_exit() {
  local rc="$1"
  if (( rc != 0 )) && [[ "${SERVER_DECOMMISSIONED}" == "true" ]] && [[ -n "${REGIONSERVER_SERVER_NAME}" ]]; then
    echo "Recommissioning ${REGIONSERVER_SERVER_NAME} after failed memberLeave..."
    recommission_regionserver "${REGIONSERVER_SERVER_NAME}" || rc=1
  fi
  exit "${rc}"
}

trap 'cleanup_on_exit $?' EXIT
trap '[[ -n "${REGIONMOVER_PID}" ]] && kill "${REGIONMOVER_PID}" 2>/dev/null || true; exit 143' TERM INT HUP

if [[ ! "${REGIONMOVER_TIMEOUT_SECONDS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "REGIONMOVER_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 1
fi

REGIONSERVER_SERVER_NAME="$(get_regionserver_server_name)" || {
  echo "Failed to resolve HBase ServerName for ${REGIONSERVER_HOST}:${REGIONSERVER_PORT}" >&2
  exit 1
}

# ponytail: use per-server decommissioning instead of global balancer toggles; revisit only if HBase admin APIs prove insufficient in production.
echo "Decommissioning ${REGIONSERVER_SERVER_NAME} before unload..."
decommission_regionserver "${REGIONSERVER_SERVER_NAME}"
SERVER_DECOMMISSIONED=true

echo "Unloading regions from ${REGIONSERVER_HOST}..."
"${HBASE_HOME}/bin/hbase" org.apache.hadoop.hbase.util.RegionMover \
  -m 6 \
  -t "${REGIONMOVER_TIMEOUT_SECONDS}" \
  -r "${REGIONSERVER_HOST}" \
  -o unload &
REGIONMOVER_PID=$!
wait "${REGIONMOVER_PID}"
REGIONMOVER_PID=""

region_count="$(get_regionserver_region_count "${REGIONSERVER_SERVER_NAME}")" || {
  echo "Failed to read region count for ${REGIONSERVER_SERVER_NAME}" >&2
  exit 1
}
if [[ "${region_count}" != "0" ]]; then
  echo "RegionServer ${REGIONSERVER_SERVER_NAME} still hosts ${region_count} region(s) after unload" >&2
  exit 1
fi

SERVER_DECOMMISSIONED=false
echo "RegionServer ${REGIONSERVER_SERVER_NAME} drained successfully"
