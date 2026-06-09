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
  }
  After "cleanup"

  It "restores into an empty data directory"
    When run bash ../dataprotection/restore.sh
    The status should be success
    The stdout should include "INFO: Restore complete."
    The file "${data_dir}/restored.txt" should be exist
    The file "${data_dir}/.kb-data-protection" should not be exist
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
End
