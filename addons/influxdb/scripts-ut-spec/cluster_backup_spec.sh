# shellcheck shell=bash

Describe "InfluxDB cluster export deduplication and restore"
  setup() {
    test_dir=$(mktemp -d)
    scripts="${SHELLSPEC_CWD:?}/addons/influxdb/dataprotection"

    # Mock influx CLI
    cat > "$test_dir/influx" <<'MOCK'
#!/usr/bin/env bash
set -eu
query=""
is_import=0
import_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -execute) query="$2"; shift 2 ;;
    -import) is_import=1; shift ;;
    -path=*) import_path="${1#-path=}"; shift ;;
    *) shift ;;
  esac
done

if [[ $is_import -eq 1 ]]; then
  printf '%s\n' "$import_path" >> "$DP_BACKUP_BASE_PATH/imported"
  exit 0
fi

case "$query" in
  "SHOW SERVERS")
    cat <<'EOF'
name,id,http_addr,tcp_addr
data_nodes,4,influxdb-cluster-data-0.local:8086,influxdb-cluster-data-0.local:8088
data_nodes,5,influxdb-cluster-data-1.local:8086,influxdb-cluster-data-1.local:8088
EOF
    ;;
  "SHOW SHARDS")
    cat <<'EOF'
name,id,database,retention_policy,shard_group,start_time,end_time,expiry_time,owners
_internal,8,_internal,monitor,5,2026-11-14T00:00:00Z,2026-11-15T00:00:00Z,2026-11-22T00:00:00Z,4
_internal,9,_internal,monitor,5,2026-11-14T00:00:00Z,2026-11-15T00:00:00Z,2026-11-22T00:00:00Z,5
db_a,27,db_a,autogen,17,2026-11-16T00:00:00Z,2026-11-23T00:00:00Z,2026-11-23T00:00:00Z,"5,4"
EOF
    ;;
  "SHOW DATABASES")
    cat <<'EOF'
name: databases
name
----
_internal
db_a
EOF
    ;;
  "SHOW RETENTION POLICIES")
    cat <<'EOF'
name,duration,shardGroupDuration,replicaN,default
autogen,0s,168h0m0s,2,true
EOF
    ;;
  *)
    exit 0
    ;;
esac
MOCK

    # Mock influx_inspect
    cat > "$test_dir/influx_inspect" <<'MOCK'
#!/usr/bin/env bash
set -eu
out_file=""
data_dir=""
database=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -out) out_file="$2"; shift 2 ;;
    -datadir) data_dir="$2"; shift 2 ;;
    -database) database="$2"; shift 2 ;;
    *) shift ;;
  esac
done

mkdir -p "$(dirname "$out_file")"
# If data_dir has shard directories for this database, export data; otherwise export empty header
if [[ -d "$data_dir/$database" && -n $(find "$data_dir/$database" -type d -name "27" 2>/dev/null) ]]; then
  printf 'DATA_POINTS_FOR_%s\n' "$database" | gzip > "$out_file"
else
  printf '# INFLUXDB EXPORT\n# DDL\n# DML\n' | gzip > "$out_file"
fi
MOCK

    # Mock datasafed
    cat > "$test_dir/datasafed" <<'MOCK'
#!/usr/bin/env bash
set -eu
case "$1" in
  push)
    dest="$DATASAFED_BACKEND_BASE_PATH/$3"
    mkdir -p "$(dirname "$dest")"
    if [[ -f "$2" ]]; then
      cp "$2" "$dest"
    else
      cat > "$dest"
    fi
    ;;
  pull)
    src="$DATASAFED_BACKEND_BASE_PATH/${2#/}"
    if [[ $# -ge 3 ]]; then
      mkdir -p "$(dirname "$3")"
      cp "$src" "$3"
    else
      cat "$src"
    fi
    ;;
  stat)
    printf 'TotalSize: 2048\n'
    ;;
  list)
    find "$DATASAFED_BACKEND_BASE_PATH" -type f | sed "s|^$DATASAFED_BACKEND_BASE_PATH/||"
    ;;
esac
MOCK
    chmod +x "$test_dir/influx" "$test_dir/influx_inspect" "$test_dir/datasafed"

    # Prepare mock local shard data for both nodes
    data_dir_0="$test_dir/data_node_0"
    data_dir_1="$test_dir/data_node_1"
    mkdir -p "$data_dir_0/data/db_a/autogen/27" "$data_dir_0/wal/db_a/autogen/27"
    mkdir -p "$data_dir_1/data/db_a/autogen/27" "$data_dir_1/wal/db_a/autogen/27"
    echo "tsm_data_0" > "$data_dir_0/data/db_a/autogen/27/00001.tsm"
    echo "tsm_data_1" > "$data_dir_1/data/db_a/autogen/27/00001.tsm"
  }

  cleanup() {
    rm -rf "$test_dir"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  It "deduplicates replica shards by exporting from min-owner node only"
    # Run backup on Node 0 (target pod: influxdb-cluster-data-0 -> Node ID 4)
    cat "$scripts/cluster-common.sh" "$scripts/selection.sh" "$scripts/cluster-backup.sh" | env \
      PATH="$test_dir:$PATH" DP_DATASAFED_BIN_PATH="$test_dir" \
      DATA_DIR="$data_dir_0" DP_DB_HOST=127.0.0.1 DP_DB_PASSWORD=pwd \
      DP_BACKUP_BASE_PATH="$test_dir/repo/influxdb-cluster-data-0" \
      DP_BACKUP_INFO_FILE="$test_dir/info_0" \
      DP_TARGET_POD_NAME="influxdb-cluster-data-0" \
      bash

    # Run backup on Node 1 (target pod: influxdb-cluster-data-1 -> Node ID 5)
    cat "$scripts/cluster-common.sh" "$scripts/selection.sh" "$scripts/cluster-backup.sh" | env \
      PATH="$test_dir:$PATH" DP_DATASAFED_BIN_PATH="$test_dir" \
      DATA_DIR="$data_dir_1" DP_DB_HOST=127.0.0.1 DP_DB_PASSWORD=pwd \
      DP_BACKUP_BASE_PATH="$test_dir/repo/influxdb-cluster-data-1" \
      DP_BACKUP_INFO_FILE="$test_dir/info_1" \
      DP_TARGET_POD_NAME="influxdb-cluster-data-1" \
      bash

    # Node 0 (primary min-owner=4) should export actual data
    node0_out="$test_dir/repo/influxdb-cluster-data-0/export_db_a.lp.gz"
    The file "$node0_out" should be exist
    The contents of file <(gzip -dc "$node0_out") should eq "DATA_POINTS_FOR_db_a"

    # Node 1 (replica owner=5) should skip data export and generate empty header archive
    node1_out="$test_dir/repo/influxdb-cluster-data-1/export_db_a.lp.gz"
    The file "$node1_out" should be exist
    The contents of file <(gzip -dc "$node1_out") should eq "$(printf '# INFLUXDB EXPORT\n# DDL\n# DML')"

    # Staging directories should be completely cleaned up on both nodes
    # shellcheck disable=SC2034
    staging_0=$(find "$data_dir_0" -maxdepth 1 -name ".stage_export_*" 2>/dev/null)
    # shellcheck disable=SC2034
    staging_1=$(find "$data_dir_1" -maxdepth 1 -name ".stage_export_*" 2>/dev/null)
    The variable staging_0 should be blank
    The variable staging_1 should be blank
  End

  It "restores across multi-pod cluster backup directory layout"
    # Pre-populate multi-pod backup directory
    mkdir -p "$test_dir/repo/influxdb-cluster-data-0" "$test_dir/repo/influxdb-cluster-data-1"
    printf 'CREATE DATABASE db_a\nDATA_FROM_POD_0\n' | gzip > "$test_dir/repo/influxdb-cluster-data-0/export_db_a.lp.gz"
    printf '# INFLUXDB EXPORT\n# DDL\n# DML\n' | gzip > "$test_dir/repo/influxdb-cluster-data-1/export_db_a.lp.gz"

    # Run cluster restore
    cat "$scripts/cluster-common.sh" "$scripts/selection.sh" "$scripts/cluster-restore.sh" | env \
      PATH="$test_dir:$PATH" DP_DATASAFED_BIN_PATH="$test_dir" \
      DP_DB_HOST=127.0.0.1 DP_DB_PASSWORD=pwd \
      DP_BACKUP_BASE_PATH="$test_dir/repo/influxdb-cluster-data-0" \
      DP_TARGET_RELATIVE_PATH="influxdb-cluster-data-0" \
      bash

    The file "$test_dir/repo/influxdb-cluster-data-0/imported" should be exist
    The lines of contents of file "$test_dir/repo/influxdb-cluster-data-0/imported" should eq 2
  End

  It "exports and restores selective retention policies with deduplication"
    # Run selective backup on Node 0 (primary min-owner=4)
    cat "$scripts/cluster-common.sh" "$scripts/selection.sh" "$scripts/cluster-backup.sh" | env \
      PATH="$test_dir:$PATH" DP_DATASAFED_BIN_PATH="$test_dir" \
      DATA_DIR="$data_dir_0" DP_DB_HOST=127.0.0.1 DP_DB_PASSWORD=pwd \
      DP_BACKUP_BASE_PATH="$test_dir/repo/influxdb-cluster-data-0" \
      DP_BACKUP_INFO_FILE="$test_dir/info_0" \
      DP_TARGET_POD_NAME="influxdb-cluster-data-0" \
      selection='"db_a"/"autogen"' \
      bash

    # Run selective backup on Node 1 (replica owner=5)
    cat "$scripts/cluster-common.sh" "$scripts/selection.sh" "$scripts/cluster-backup.sh" | env \
      PATH="$test_dir:$PATH" DP_DATASAFED_BIN_PATH="$test_dir" \
      DATA_DIR="$data_dir_1" DP_DB_HOST=127.0.0.1 DP_DB_PASSWORD=pwd \
      DP_BACKUP_BASE_PATH="$test_dir/repo/influxdb-cluster-data-1" \
      DP_BACKUP_INFO_FILE="$test_dir/info_1" \
      DP_TARGET_POD_NAME="influxdb-cluster-data-1" \
      selection='"db_a"/"autogen"' \
      bash

    # Verify selective archive layout and deduplication
    node0_sel="$test_dir/repo/influxdb-cluster-data-0/selected/db_a/rp/autogen/data.lp.gz"
    node1_sel="$test_dir/repo/influxdb-cluster-data-1/selected/db_a/rp/autogen/data.lp.gz"
    The file "$node0_sel" should be exist
    The file "$node1_sel" should be exist
    The contents of file <(gzip -dc "$node0_sel") should eq "DATA_POINTS_FOR_db_a"
    The contents of file <(gzip -dc "$node1_sel") should eq "$(printf '# INFLUXDB EXPORT\n# DDL\n# DML')"

    # Run selective restore
    cat "$scripts/cluster-common.sh" "$scripts/selection.sh" "$scripts/cluster-restore.sh" | env \
      PATH="$test_dir:$PATH" DP_DATASAFED_BIN_PATH="$test_dir" \
      DP_DB_HOST=127.0.0.1 DP_DB_PASSWORD=pwd \
      DP_BACKUP_BASE_PATH="$test_dir/repo/influxdb-cluster-data-0" \
      DP_TARGET_RELATIVE_PATH="influxdb-cluster-data-0" \
      selection='"db_a"/"autogen"' \
      bash

    The file "$test_dir/repo/influxdb-cluster-data-0/imported" should be exist
    The lines of contents of file "$test_dir/repo/influxdb-cluster-data-0/imported" should eq 2
  End
End
