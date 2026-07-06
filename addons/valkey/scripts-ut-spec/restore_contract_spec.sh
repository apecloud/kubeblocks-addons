# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey restore contract"
  setup() {
    original_path="${PATH}"
    spec_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/valkey-restore-spec.XXXXXX")
    data_dir="${spec_tmp_dir}/data"
    fakebin="${spec_tmp_dir}/fakebin"
    mkdir -p "${data_dir}" "${fakebin}"

    cat > "${fakebin}/datasafed" <<'SH'
#!/usr/bin/env bash
set -e

case "$1" in
  list)
    printf '%s\n' "$2"
    ;;
  pull)
    tmp="${TMPDIR:-/tmp}/valkey-datasafed-fake.$$"
    rm -rf "${tmp}"
    mkdir -p "${tmp}/src"
    printf 'restored\n' > "${tmp}/src/restored.txt"
    if [ "${FAKE_DATASAFED_OMIT_RDB:-}" != "1" ]; then
      if [ "${FAKE_DATASAFED_EMPTY_RDB:-}" = "1" ]; then
        : > "${tmp}/src/dump.rdb"
      else
        printf 'valkey-rdb\n' > "${tmp}/src/dump.rdb"
      fi
    fi
    if [ "${FAKE_DATASAFED_INCLUDE_AOF:-}" = "1" ]; then
      mkdir -p "${tmp}/src/appendonlydir"
      printf 'existing manifest\n' > "${tmp}/src/appendonlydir/appendonly.aof.manifest"
    fi
    if [ "${FAKE_DATASAFED_INCLUDE_ROOT_AOF:-}" = "1" ]; then
      printf 'existing aof\n' > "${tmp}/src/appendonly.aof"
    fi
    if [ -n "${FAKE_DATASAFED_CLUSTER_META:-}" ]; then
      printf 'source_shards=%s\n' "${FAKE_DATASAFED_CLUSTER_META}" > "${tmp}/src/cluster-meta"
    fi
    tar -cf - -C "${tmp}/src" .
    rm -rf "${tmp}"
    ;;
  *)
    exit 1
    ;;
esac
SH

    cat > "${fakebin}/tar" <<'SH'
#!/usr/bin/env bash
set -e

if [ "$1" = "-xvf" ] && [ "$2" = "-" ] && [ "$3" = "-C" ]; then
  /usr/bin/tar -xf - -C "$4"
  exit 0
fi

exec /usr/bin/tar "$@"
SH
    chmod +x "${fakebin}/datasafed" "${fakebin}/tar"

    export DATA_DIR="${data_dir}"
    export DP_BACKUP_NAME="restore-test"
    export DP_BACKUP_BASE_PATH="/backup"
    export DP_DATASAFED_BIN_PATH="${fakebin}"
    export PATH="${fakebin}:${PATH}"
  }
  Before "setup"

  cleanup() {
    rm -rf "${spec_tmp_dir:-}"
    export PATH="${original_path}"
    unset DATA_DIR
    unset DP_BACKUP_NAME
    unset DP_BACKUP_BASE_PATH
    unset DP_DATASAFED_BIN_PATH
    unset FAKE_DATASAFED_INCLUDE_AOF
    unset FAKE_DATASAFED_INCLUDE_ROOT_AOF
    unset FAKE_DATASAFED_OMIT_RDB
    unset FAKE_DATASAFED_EMPTY_RDB
    unset FAKE_DATASAFED_CLUSTER_META
    unset RESTORE_TARGET_SHARDS
  }
  After "cleanup"

  It "restores into an empty data directory"
    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should include "INFO: Restore complete."
    The file "${data_dir}/restored.txt" should be exist
    The file "${data_dir}/appendonlydir/appendonly.aof.manifest" should be exist
    The file "${data_dir}/appendonlydir/appendonly.aof.1.base.rdb" should be exist
    The file "${data_dir}/appendonlydir/appendonly.aof.1.incr.aof" should be exist
    The file "${data_dir}/.kb-data-protection" should not be exist
  End

  It "seeds a multipart AOF manifest from the restored RDB"
    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should include "INFO: Seeded multipart AOF manifest from restored dump.rdb."
    The contents of file "${data_dir}/appendonlydir/appendonly.aof.manifest" should include "file appendonly.aof.1.base.rdb seq 1 type b"
    The contents of file "${data_dir}/appendonlydir/appendonly.aof.manifest" should include "file appendonly.aof.1.incr.aof seq 1 type i"
    The contents of file "${data_dir}/appendonlydir/appendonly.aof.1.base.rdb" should include "valkey-rdb"
  End

  It "restores when only the data-protection placeholder exists"
    touch "${data_dir}/.kb-data-protection"

    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should include "INFO: Restore complete."
    The file "${data_dir}/restored.txt" should be exist
    The file "${data_dir}/.kb-data-protection" should not be exist
  End

  It "fails closed when the placeholder exists alongside real data"
    touch "${data_dir}/.kb-data-protection"
    printf 'existing\n' > "${data_dir}/appendonly.aof"

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stderr should include "ERROR: ${data_dir} is not empty"
    The file "${data_dir}/restored.txt" should not be exist
  End

  It "fails closed when the restored archive is missing dump.rdb"
    export FAKE_DATASAFED_OMIT_RDB=1

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should include "ERROR: restored archive must contain a non-empty dump.rdb."
  End

  It "fails closed when the restored dump.rdb is empty"
    export FAKE_DATASAFED_EMPTY_RDB=1

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should include "ERROR: restored archive must contain a non-empty dump.rdb."
  End

  It "fails closed when the restored archive already contains an AOF directory"
    export FAKE_DATASAFED_INCLUDE_AOF=1

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should include "ERROR: restored archive already contains AOF state"
    The stderr should include "appendonlydir"
  End

  It "fails closed when the restored archive already contains root AOF state"
    export FAKE_DATASAFED_INCLUDE_ROOT_AOF=1

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should include "ERROR: restored archive already contains AOF state"
    The stderr should include "appendonly.aof"
  End
  It "rejects a cluster restore when target shard count differs (fail-fast)"
    export FAKE_DATASAFED_CLUSTER_META=3
    export RESTORE_TARGET_SHARDS=4

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should include "shard count mismatch"
    The stderr should include "backup taken from 3 shard(s), target declares 4"
  End

  It "verifies and cleans cluster-meta when shard counts match"
    export FAKE_DATASAFED_CLUSTER_META=3
    export RESTORE_TARGET_SHARDS=3

    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should include "cluster restore shard count verified (3)"
    The file "${data_dir}/cluster-meta" should not be exist
  End

  It "warns loudly when cluster-meta exists but no target count is provided"
    export FAKE_DATASAFED_CLUSTER_META=5

    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should include "WARNING"
    The stdout should include "source_shards=5"
    The file "${data_dir}/cluster-meta" should not be exist
  End
End
