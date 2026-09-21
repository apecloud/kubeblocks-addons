# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey restore contract (redis-aligned)"
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
    # The .tar.zst of the backup can be made absent so the fallback chain
    # (valkey-offline.tar, then .tar.gz) can be exercised.
    if [ "$2" = "${DP_BACKUP_NAME}.tar.zst" ] && [ "${FAKE_DATASAFED_ABSENT_ZST:-}" = "1" ]; then
      exit 0
    fi
    if [ "$2" = "valkey-offline.tar" ] && [ "${FAKE_DATASAFED_OFFLINE:-}" != "1" ]; then
      exit 0
    fi
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
      printf 'existing base\n' > "${tmp}/src/appendonlydir/appendonly.aof.1.base.rdb"
    fi
    tar -cf - -C "${tmp}/src" .
    rm -rf "${tmp}"
    ;;
  *)
    exit 1
    ;;
esac
SH

    # restore.sh extracts with -xvf (zst / offline) or -xzvf (gzip fallback).
    cat > "${fakebin}/tar" <<'SH'
#!/usr/bin/env bash
set -e

if [ "${1}" = "-xvf" ] && [ "$2" = "-" ] && [ "$3" = "-C" ]; then
  /usr/bin/tar -xf - -C "$4"
  exit 0
fi
if [ "${1}" = "-xzvf" ] && [ "$2" = "-" ] && [ "$3" = "-C" ]; then
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
    unset DP_RESTORE_KEY_PATTERNS
    unset FAKE_DATASAFED_INCLUDE_AOF
    unset FAKE_DATASAFED_OMIT_RDB
    unset FAKE_DATASAFED_EMPTY_RDB
    unset FAKE_DATASAFED_ABSENT_ZST
    unset FAKE_DATASAFED_OFFLINE
  }
  Before "setup"

  cleanup() {
    rm -rf "${spec_tmp_dir:-}"
    export PATH="${original_path}"
    unset DATA_DIR
    unset DP_BACKUP_NAME
    unset DP_BACKUP_BASE_PATH
    unset DP_DATASAFED_BIN_PATH
    unset DP_RESTORE_KEY_PATTERNS
    unset FAKE_DATASAFED_INCLUDE_AOF
    unset FAKE_DATASAFED_OMIT_RDB
    unset FAKE_DATASAFED_EMPTY_RDB
    unset FAKE_DATASAFED_ABSENT_ZST
    unset FAKE_DATASAFED_OFFLINE
  }
  After "cleanup"

  It "restores the whole archived directory into an empty data directory"
    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should include "INFO: Restore complete."
    The file "${data_dir}/restored.txt" should be exist
    The file "${data_dir}/dump.rdb" should be exist
    The file "${data_dir}/.kb-data-protection" should not be exist
  End

  It "restores an archive that already carries AOF state as-is"
    # redis parity: the archive is the on-disk state of the data directory, so
    # no manifest is synthesised from dump.rdb.
    export FAKE_DATASAFED_INCLUDE_AOF=1

    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should not include "Seeded multipart AOF manifest"
    The contents of file "${data_dir}/appendonlydir/appendonly.aof.manifest" should include "existing manifest"
    The file "${data_dir}/appendonlydir/appendonly.aof.1.base.rdb" should be exist
  End

  It "does not require dump.rdb inside the archive (redis parity)"
    export FAKE_DATASAFED_OMIT_RDB=1

    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should include "INFO: Restore complete."
    The file "${data_dir}/restored.txt" should be exist
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

  It "falls back to valkey-offline.tar when the backup archive is absent"
    export FAKE_DATASAFED_ABSENT_ZST=1
    export FAKE_DATASAFED_OFFLINE=1

    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should include "INFO: Restoring from valkey-offline.tar..."
    The file "${data_dir}/restored.txt" should be exist
  End
End

Describe "Valkey restore data-dir switch (DP_RESTORE_KEY_PATTERNS)"
  switch_in_dir() {
    # Source the fragment the way prepareData concatenates it, then print the
    # DATA_DIR the following restore.sh would see.
    ( export DATA_DIR="$1"
      if [ "${2:-}" != "" ]; then export DP_RESTORE_KEY_PATTERNS="$2"; else unset DP_RESTORE_KEY_PATTERNS; fi
      # shellcheck source=/dev/null
      . ../dataprotection/switch-data-dir.sh >/dev/null
      printf '%s' "${DATA_DIR}" )
  }

  It "keeps DATA_DIR when DP_RESTORE_KEY_PATTERNS is not set"
    When call switch_in_dir "/data" ""
    The status should be success
    The stdout should eq "/data"
  End

  It "reroutes DATA_DIR to .restore_keys when DP_RESTORE_KEY_PATTERNS is set"
    When call switch_in_dir "/data" "user:*,session:*"
    The status should be success
    The stdout should eq "/data/.restore_keys"
  End
End
