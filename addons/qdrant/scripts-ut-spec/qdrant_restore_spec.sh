# shellcheck shell=bash

Describe "Qdrant Restore Bash Script Tests"
  It "retries after a transient snapshot transport failure"
    restore_tmp_dir="$(mktemp -d)"
    cat > "${restore_tmp_dir}/common.sh" <<'COMMON'
qdrant_set_tls_variables() {
  SCHEME=http
  CURL_TLS=""
}

datasafed() {
  case "$1:$2" in
    list:/) printf '%s\n' pod-0 ;;
    list:/pod-0/) printf '%s\n' /pod-0/test.snapshot ;;
    pull:*) printf '%s\n' snapshot-data ;;
  esac
}

qdrant_curl() {
  cat >/dev/null
  count_file="${RESTORE_TEST_TMP}/attempts"
  attempt=0
  [ ! -f "$count_file" ] || attempt="$(cat "$count_file")"
  attempt=$((attempt + 1))
  printf '%s\n' "$attempt" > "$count_file"
  if [ "$attempt" -eq 1 ]; then
    printf '%s\n' 'transient upload failure'
    return 22
  fi
  printf '%s\n' '{"status":"ok"}'
}

sleep() { :; }
COMMON

    When run env \
      RESTORE_TEST_TMP="$restore_tmp_dir" \
      QDRANT_COMMON_FILE="${restore_tmp_dir}/common.sh" \
      DP_DATASAFED_BIN_PATH="${restore_tmp_dir}" \
      DP_BACKUP_BASE_PATH="${restore_tmp_dir}/backup/pod-0" \
      DP_DB_HOST="qdrant" \
      bash ../scripts/qdrant-restore.sh
    The status should be success
    The output should include "failed to restore collection test in pod-0, retry"
    The output should include "restore collection test in pod-0 successfully"
    The contents of file "${restore_tmp_dir}/attempts" should eq "2"

    rm -rf "$restore_tmp_dir"
  End
End