# shellcheck shell=bash

Describe "dataprotection/common-scripts.sh backup-info publication"
  Include ../dataprotection/common-scripts.sh

  setup() {
    tmpdir=$(mktemp -d -t pg-common-backup-info-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    DP_BACKUP_INFO_FILE="${tmpdir}/backup-info"
    export PATH DP_BACKUP_INFO_FILE
    unset MV_EXIT 2>/dev/null || true
    write_stubs
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  write_stubs() {
    cat > "${bindir}/mv" <<'EOF'
#!/bin/sh
if [ "${MV_EXIT:-0}" -ne 0 ]; then
  exit "${MV_EXIT}"
fi
exec /bin/mv "$@"
EOF
    chmod +x "${bindir}/mv"
  }

  publish_with_existence_observer() {
    (
      echo() {
        case "$1" in
          '{"totalSize"'*) /bin/sleep 0.2 ;;
        esac
        builtin echo "$@"
      }
      (
        for _ in {1..200}; do
          if [[ -e "${DP_BACKUP_INFO_FILE}" ]]; then
            /usr/bin/wc -c < "${DP_BACKUP_INFO_FILE}" > "${tmpdir}/observed-bytes"
            exit 0
          fi
          /bin/sleep 0.01
        done
        printf '0\n' > "${tmpdir}/observed-bytes"
        exit 1
      ) &
      observer_pid=$!
      DP_save_backup_status_info "4096" "2026-08-15T17:00:00Z" \
        "2026-08-15T17:01:00Z"
      wait "${observer_pid}"
    )
  }

  observed_bytes() {
    tr -d '[:space:]' < "${tmpdir}/observed-bytes"
  }

  backup_info_temp_count() {
    find "${tmpdir}" -maxdepth 1 -name 'backup-info.tmp.*' -print | wc -l | tr -d '[:space:]'
  }

  It "publishes a complete document before the final path is visible"
    When call publish_with_existence_observer
    The status should eq 0
    The result of function observed_bytes should not eq 0
    The contents of file "${DP_BACKUP_INFO_FILE}" should eq '{"totalSize":"4096","extras":[],"timeRange":{"start":"2026-08-15T17:00:00Z","end":"2026-08-15T17:01:00Z"}}'
  End

  It "preserves the size-only document shape"
    When call DP_save_backup_status_info "0"
    The status should eq 0
    The contents of file "${DP_BACKUP_INFO_FILE}" should eq '{"totalSize":"0"}'
  End

  It "preserves end time, timezone, and extras without a start time"
    When call DP_save_backup_status_info "4096" "" "2026-08-15T17:01:00Z" \
      "+08:00" '{"source":"archive"}'
    The status should eq 0
    The contents of file "${DP_BACKUP_INFO_FILE}" should eq '{"totalSize":"4096","extras":[{"source":"archive"}],"timeRange":{"end":"2026-08-15T17:01:00Z","timeZone":"+08:00"}}'
  End

  It "fails without leaving metadata when atomic publication fails"
    export MV_EXIT=7
    When call DP_save_backup_status_info "4096" "2026-08-15T17:00:00Z" \
      "2026-08-15T17:01:00Z"
    The status should be failure
    The path "${DP_BACKUP_INFO_FILE}" should not be exist
    The result of function backup_info_temp_count should eq 0
  End
End
