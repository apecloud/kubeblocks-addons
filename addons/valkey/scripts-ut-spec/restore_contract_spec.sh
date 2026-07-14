# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey restore contract"
  setup() {
    original_path="${PATH}"
    spec_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/valkey-restore-spec.XXXXXX")
    spec_tmp_dir=$(cd -P "${spec_tmp_dir}" && pwd -P)
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
    if [ "${FAKE_DATASAFED_SYMLINK_RDB:-}" = "1" ]; then
      printf 'valkey-rdb\n' > "${tmp}/src/restored-rdb-target"
      ln -s restored-rdb-target "${tmp}/src/dump.rdb"
    elif [ "${FAKE_DATASAFED_OMIT_RDB:-}" != "1" ]; then
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
      {
        printf 'source_shards=%s\n' "${FAKE_DATASAFED_CLUSTER_META}"
        [ "${FAKE_DATASAFED_OMIT_MASTER_ID:-0}" = "1" ] || \
          printf 'shard_master_id=%s\n' "${FAKE_DATASAFED_MASTER_ID:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
        [ "${FAKE_DATASAFED_OMIT_SLOT_RANGES:-0}" = "1" ] || \
          printf 'shard_slot_ranges=%s\n' "${FAKE_DATASAFED_SLOT_RANGES:-0-5460}"
        [ "${FAKE_DATASAFED_OMIT_RDB_SHA:-0}" = "1" ] || \
          printf 'rdb_sha256=%s\n' "${FAKE_DATASAFED_RDB_SHA:-$(sha256sum "${tmp}/src/dump.rdb" | awk '{print $1}')}"
      } > "${tmp}/src/cluster-meta"
    fi
    if [ "${FAKE_DATASAFED_PULL_FAIL:-}" = "1" ]; then
      printf 'partial\n' > "${tmp}/src/partial.txt"
      tar -cf - -C "${tmp}/src" .
      rm -rf "${tmp}"
      exit 1
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
    unset FAKE_DATASAFED_SYMLINK_RDB
    unset FAKE_DATASAFED_CLUSTER_META
    unset FAKE_DATASAFED_MASTER_ID
    unset FAKE_DATASAFED_SLOT_RANGES
    unset FAKE_DATASAFED_OMIT_MASTER_ID
    unset FAKE_DATASAFED_OMIT_SLOT_RANGES
    unset FAKE_DATASAFED_OMIT_RDB_SHA
    unset FAKE_DATASAFED_RDB_SHA
    unset FAKE_DATASAFED_PULL_FAIL
    unset RESTORE_TARGET_SHARDS
    unset VALKEY_APPEND_DIRNAME
    unset VALKEY_APPEND_FILENAME
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

  It "rejects a dot-segment DATA_DIR before any restore write"
    export DATA_DIR="${data_dir}/.."

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stderr should include "dot-segment aliases"
    The file "${spec_tmp_dir}/restored.txt" should not be exist
  End

  It "rejects an escaping append directory before any restore write"
    export VALKEY_APPEND_DIRNAME="../outside-aof"

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stderr should include "unsafe VALKEY_APPEND_DIRNAME"
    The dir "${spec_tmp_dir}/outside-aof" should not be exist
  End

  It "rejects an explicitly empty append directory before any restore write"
    export VALKEY_APPEND_DIRNAME=""

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stderr should include "unsafe VALKEY_APPEND_DIRNAME"
  End

  It "rejects a slash-bearing append filename before any restore write"
    export VALKEY_APPEND_FILENAME="nested/appendonly.aof"

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stderr should include "unsafe VALKEY_APPEND_FILENAME"
    The dir "${data_dir}/nested" should not be exist
  End

  It "rejects an explicitly empty append filename before any restore write"
    export VALKEY_APPEND_FILENAME=""

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stderr should include "unsafe VALKEY_APPEND_FILENAME"
  End

  It "rejects a dangling data-protection placeholder symlink before writing"
    outside_placeholder="${spec_tmp_dir}/outside-placeholder"
    ln -s "${outside_placeholder}" "${data_dir}/.kb-data-protection"

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stderr should include "not a safe regular file"
    The file "${outside_placeholder}" should not be exist
  End

  It "removes partial payload when archive extraction fails"
    export FAKE_DATASAFED_PULL_FAIL=1

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should include "restore archive extraction failed"
    The file "${data_dir}/partial.txt" should not be exist
    The file "${data_dir}/.kb-data-protection" should be exist
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
    The stderr should include "ERROR: restored archive must contain a safe regular non-empty dump.rdb."
  End

  It "fails closed when the restored dump.rdb is empty"
    export FAKE_DATASAFED_EMPTY_RDB=1

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should include "ERROR: restored archive must contain a safe regular non-empty dump.rdb."
  End

  It "fails closed when the restored dump.rdb is a symlink"
    export FAKE_DATASAFED_SYMLINK_RDB=1

    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should include "safe regular non-empty dump.rdb"
    The file "${data_dir}/appendonlydir/appendonly.aof.manifest" should not be exist
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
  It "prepares a valid cluster archive and preserves slot metadata for postProvision"
    export FAKE_DATASAFED_CLUSTER_META=3

    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stdout should include "Validated cluster restore metadata"
    The file "${data_dir}/cluster-meta" should be exist
    The contents of file "${data_dir}/cluster-meta" should include "shard_slot_ranges=0-5460"
    The contents of file "${data_dir}/cluster-meta" should include "rdb_sha256="
    The contents of file "${data_dir}/.kb-cluster-restore-state" should include "phase=prepared"
    The contents of file "${data_dir}/.kb-cluster-restore-state" should include "meta_sha256="
    The file "${data_dir}/appendonlydir/appendonly.aof.manifest" should be exist
  End

  It "rejects cluster metadata whose dump.rdb digest does not match the archive"
    export FAKE_DATASAFED_CLUSTER_META=3
    export FAKE_DATASAFED_RDB_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should include "dump.rdb does not match cluster-meta rdb_sha256"
    The file "${data_dir}/dump.rdb" should not be exist
    The file "${data_dir}/cluster-meta" should not be exist
    The file "${data_dir}/.kb-cluster-restore-state" should not be exist
  End

  It "rejects old cluster metadata that lacks the restored RDB identity"
    export FAKE_DATASAFED_CLUSTER_META=3
    export FAKE_DATASAFED_OMIT_RDB_SHA=1
    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should include "cluster-meta missing rdb_sha256"
    The file "${data_dir}/dump.rdb" should not be exist
    The file "${data_dir}/cluster-meta" should not be exist
    The file "${data_dir}/.kb-cluster-restore-state" should not be exist
  End

  It "fails malformed cluster metadata and re-emits the true reason on retry"
    export FAKE_DATASAFED_CLUSTER_META=3
    export FAKE_DATASAFED_OMIT_SLOT_RANGES=1
    When run bash -c "bash ../dataprotection/restore.sh; bash ../dataprotection/restore.sh"
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should not include "is not empty"
    The stderr should include "cluster-meta missing shard_slot_ranges"
    The file "${data_dir}/dump.rdb" should not be exist
    The file "${data_dir}/cluster-meta" should not be exist
  End

  It "rejects overlapping or out-of-domain slot ranges without leaving extracted data"
    export FAKE_DATASAFED_CLUSTER_META=3
    export FAKE_DATASAFED_SLOT_RANGES="0-100,100-5460"
    mkdir -p "${data_dir}/lost+found"
    When run bash ../dataprotection/restore.sh
    The status should be failure
    The stdout should include "INFO: Restoring from restore-test.tar.zst..."
    The stderr should include "invalid shard_slot_ranges"
    The file "${data_dir}/.kb-data-protection" should be exist
    The file "${data_dir}/dump.rdb" should not be exist
    The dir "${data_dir}/lost+found" should be exist
  End

  It "leaves non-cluster restores untouched by the cluster guard"
    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should include "INFO: Restore complete."
    The file "${data_dir}/.kb-cluster-restore-state" should not be exist
  End
End
