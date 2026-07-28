# shellcheck shell=bash disable=SC1091,SC2016

Describe "MongoDB backup info collector contract"
  setup_backup_info_collector() {
    test_root=$(mktemp -d "${TMPDIR:-/tmp}/mongodb-backup-info-spec.XXXXXX")
    fake_bin="$test_root/bin"
    original_path=$PATH
    real_mv=$(command -v mv)
    mkdir -p "$fake_bin"

    cat >"$fake_bin/whereis" <<'SH'
#!/bin/sh
printf 'mongosh: %s\n' "$MONGODB_TEST_MONGOSH_BIN"
SH

    cat >"$fake_bin/mongosh" <<'SH'
#!/bin/sh
if [ -n "${MONGODB_TEST_CLIENT_OUTPUT:-}" ]; then
  printf '%s\n' "$MONGODB_TEST_CLIENT_OUTPUT"
fi
exit "${MONGODB_TEST_CLIENT_RC:-0}"
SH

    cat >"$fake_bin/date" <<'SH'
#!/bin/sh
if [ -n "${MONGODB_TEST_DATE_OUTPUT:-}" ]; then
  printf '%s\n' "$MONGODB_TEST_DATE_OUTPUT"
fi
exit "${MONGODB_TEST_DATE_RC:-0}"
SH

    cat >"$fake_bin/datasafed" <<'SH'
#!/bin/sh
case "${1:-}" in
  stat)
    if [ -n "${MONGODB_TEST_DATASAFED_OUTPUT:-}" ]; then
      printf '%s\n' "$MONGODB_TEST_DATASAFED_OUTPUT"
    fi
    exit "${MONGODB_TEST_DATASAFED_RC:-0}"
    ;;
  push)
    cat >/dev/null
    exit 0
    ;;
esac
exit 64
SH

    cat >"$fake_bin/tar" <<'SH'
#!/bin/sh
: >"$MONGODB_TEST_TAR_MARKER"
exit 0
SH

    cat >"$fake_bin/mongodump" <<'SH'
#!/bin/sh
printf 'archive-data\n'
exit 0
SH

    cat >"$fake_bin/mv" <<'SH'
#!/bin/sh
if [ -n "${MONGODB_TEST_MV_RC:-}" ]; then
  exit "$MONGODB_TEST_MV_RC"
fi
exec "$MONGODB_TEST_REAL_MV" "$@"
SH

    chmod +x "$fake_bin/whereis" "$fake_bin/mongosh" \
      "$fake_bin/date" "$fake_bin/datasafed" "$fake_bin/tar" \
      "$fake_bin/mongodump" "$fake_bin/mv"

    export PATH="$fake_bin:$original_path"
    export MONGODB_TEST_MONGOSH_BIN="$fake_bin/mongosh"
    export MONGODB_TEST_REAL_MV="$real_mv"
    export DP_DB_USER="backup-user"
    export DP_DB_PASSWORD="backup-password"
    export DP_DB_PORT="27017"
    export DP_DB_HOST="mongodb.example"
    export DP_DATASAFED_BIN_PATH="$fake_bin"
    export DP_BACKUP_BASE_PATH="/backup/base"
    export DP_BACKUP_INFO_FILE="$test_root/backup-info.json"
    export DATA_DIR="$test_root/data"
    export MONGODB_TEST_TAR_MARKER="$test_root/tar-called"
    export MONGODB_TEST_CHILD_VERSION_FILE="$test_root/child-bash-version"
    export DP_BACKUP_NAME="backup-name"
    export PARALLEL="1"
    mkdir -p "$DATA_DIR"
    unset MONGODB_TEST_CLIENT_OUTPUT
    unset MONGODB_TEST_CLIENT_RC
    unset MONGODB_TEST_DATE_OUTPUT
    unset MONGODB_TEST_DATE_RC
    unset MONGODB_TEST_DATASAFED_OUTPUT
    unset MONGODB_TEST_DATASAFED_RC
    unset MONGODB_TEST_MV_RC
  }
  Before "setup_backup_info_collector"

  cleanup_backup_info_collector() {
    PATH=$original_path
    export PATH
    rm -rf "$test_root"
    unset test_root fake_bin original_path real_mv
    unset MONGODB_TEST_MONGOSH_BIN
    unset MONGODB_TEST_REAL_MV
    unset MONGODB_TEST_CLIENT_OUTPUT
    unset MONGODB_TEST_CLIENT_RC
    unset MONGODB_TEST_DATE_OUTPUT
    unset MONGODB_TEST_DATE_RC
    unset MONGODB_TEST_DATASAFED_OUTPUT
    unset MONGODB_TEST_DATASAFED_RC
    unset MONGODB_TEST_MV_RC
    unset DP_DB_USER DP_DB_PASSWORD DP_DB_PORT DP_DB_HOST
    unset DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH DP_BACKUP_INFO_FILE
    unset DATA_DIR MONGODB_TEST_TAR_MARKER MONGODB_TEST_CHILD_VERSION_FILE
    unset DP_BACKUP_NAME PARALLEL
  }
  After "cleanup_backup_info_collector"

  run_get_current_time() {
    source ../dataprotection/backup-info-collector.sh
    get_current_time
  }

  run_stat_and_report_file() {
    local status

    source ../dataprotection/backup-info-collector.sh
    stat_and_save_backup_info \
      "2026-07-29T00:00:00Z" "2026-07-29T00:05:00Z"
    status=$?
    if [ -f "$DP_BACKUP_INFO_FILE" ]; then
      printf 'file=present\n'
      cat "$DP_BACKUP_INFO_FILE"
    else
      printf 'file=absent\n'
    fi
    return "$status"
  }

  run_datafile_backup_and_report() {
    local child_version status tar_state info_state exit_marker residue_count

    "$SHELLSPEC_SHELL" -c '
      printf "%s\n" "$BASH_VERSION" >"$MONGODB_TEST_CHILD_VERSION_FILE"
      source ../dataprotection/backup-info-collector.sh
      source ../dataprotection/datafile-backup.sh
    '
    status=$?
    child_version=$(cat "$MONGODB_TEST_CHILD_VERSION_FILE")
    if [ -f "$MONGODB_TEST_TAR_MARKER" ]; then
      tar_state=present
    else
      tar_state=absent
    fi
    if [ -f "$DP_BACKUP_INFO_FILE" ]; then
      info_state=present
    else
      info_state=absent
    fi
    if [ -f "${DP_BACKUP_INFO_FILE}.exit" ]; then
      exit_marker=present
    else
      exit_marker=absent
    fi
    residue_count=$(find "$test_root" -maxdepth 1 -type f \
      ! -name backup-info.json ! -name tar-called \
      ! -name backup-info.json.exit ! -name child-bash-version \
      | wc -l | tr -d ' ')
    printf 'tar=%s info=%s marker=%s residue=%s child=%s\n' \
      "$tar_state" "$info_state" "$exit_marker" "$residue_count" \
      "$child_version"
    return "$status"
  }

  run_empty_time_contract() {
    local helper_status action_status

    source ../dataprotection/backup-info-collector.sh
    get_current_time >/dev/null
    helper_status=$?
    run_datafile_backup_and_report
    action_status=$?
    printf 'helper=%s action=%s\n' "$helper_status" "$action_status"
    return "$action_status"
  }

  run_stat_with_existing_destination() {
    local destination residue_count status

    printf 'previous-metadata\n' >"$DP_BACKUP_INFO_FILE"
    source ../dataprotection/backup-info-collector.sh
    stat_and_save_backup_info \
      "2026-07-29T00:00:00Z" "2026-07-29T00:05:00Z"
    status=$?
    destination=$(cat "$DP_BACKUP_INFO_FILE")
    residue_count=$(find "$test_root" -maxdepth 1 -type f \
      ! -name backup-info.json ! -name tar-called | wc -l | tr -d ' ')
    printf 'destination=%s residue=%s\n' "$destination" "$residue_count"
    return "$status"
  }

  run_mongodump_publication_failure() {
    local child_version destination exit_marker residue_count status

    printf 'previous-metadata\n' >"$DP_BACKUP_INFO_FILE"
    "$SHELLSPEC_SHELL" -c '
      printf "%s\n" "$BASH_VERSION" >"$MONGODB_TEST_CHILD_VERSION_FILE"
      source ../dataprotection/backup-info-collector.sh
      source ../dataprotection/mongodump-backup.sh
    '
    status=$?
    child_version=$(cat "$MONGODB_TEST_CHILD_VERSION_FILE")
    destination=$(cat "$DP_BACKUP_INFO_FILE")
    if [ -f "${DP_BACKUP_INFO_FILE}.exit" ]; then
      exit_marker=present
    else
      exit_marker=absent
    fi
    residue_count=$(find "$test_root" -maxdepth 1 -type f \
      ! -name backup-info.json ! -name backup-info.json.exit \
      ! -name tar-called ! -name child-bash-version | wc -l | tr -d ' ')
    printf 'destination=%s marker=%s residue=%s child=%s\n' \
      "$destination" "$exit_marker" "$residue_count" "$child_version"
    return "$status"
  }

  It "preserves the MongoDB client failure instead of fabricating a timestamp"
    export MONGODB_TEST_CLIENT_RC=17
    export MONGODB_TEST_DATE_OUTPUT="2026-07-29T00:00:00Z"

    When call run_get_current_time

    The status should equal 17
    The output should be blank
  End

  It "fails when the client timestamp cannot be converted"
    export MONGODB_TEST_CLIENT_OUTPUT="not-an-epoch"
    export MONGODB_TEST_DATE_RC=11

    When call run_get_current_time

    The status should equal 11
    The output should be blank
  End

  It "classifies empty successful MongoDB output before the datafile backup"
    export MONGODB_TEST_DATE_OUTPUT="2026-07-29T00:00:00Z"
    export MONGODB_TEST_DATASAFED_OUTPUT="TotalSize 42"

    When call run_empty_time_contract

    The status should equal 1
    The line 1 of output should equal "failed with exit code 65"
    The line 2 of output should equal "tar=absent info=absent marker=present residue=0 child=$BASH_VERSION"
    The line 3 of output should equal "helper=65 action=1"
  End

  It "classifies empty successful date output before the datafile backup"
    export MONGODB_TEST_CLIENT_OUTPUT="1753747200"
    export MONGODB_TEST_DATASAFED_OUTPUT="TotalSize 42"

    When call run_empty_time_contract

    The status should equal 1
    The line 1 of output should equal "failed with exit code 65"
    The line 2 of output should equal "tar=absent info=absent marker=present residue=0 child=$BASH_VERSION"
    The line 3 of output should equal "helper=65 action=1"
  End

  It "preserves datasafed failure and does not write backup metadata"
    export MONGODB_TEST_DATASAFED_RC=23

    When call run_stat_and_report_file

    The status should equal 23
    The output should equal "file=absent"
  End

  It "rejects a successful datasafed response without TotalSize"
    export MONGODB_TEST_DATASAFED_OUTPUT="Files 4"

    When call run_stat_and_report_file

    The status should be failure
    The output should equal "file=absent"
  End

  It "rejects an empty TotalSize value without replacing existing metadata"
    export MONGODB_TEST_DATASAFED_OUTPUT="TotalSize"

    When call run_stat_with_existing_destination

    The status should equal 65
    The output should equal "destination=previous-metadata residue=0"
  End

  It "rejects duplicate TotalSize values without replacing existing metadata"
    MONGODB_TEST_DATASAFED_OUTPUT='TotalSize 42
TotalSize 84'
    export MONGODB_TEST_DATASAFED_OUTPUT

    When call run_stat_with_existing_destination

    The status should equal 65
    The output should equal "destination=previous-metadata residue=0"
  End

  It "writes exact metadata for a valid datasafed TotalSize response"
    export MONGODB_TEST_DATASAFED_OUTPUT="TotalSize 42"

    When call run_stat_and_report_file

    The status should be success
    The line 1 of output should equal "file=present"
    The line 2 of output should equal '{"totalSize":"42","timeRange":{"start":"2026-07-29T00:00:00Z","end":"2026-07-29T00:05:00Z"}}'
  End

  It "stops the datafile backup before tar when the start timestamp fails"
    export MONGODB_TEST_CLIENT_RC=17
    export MONGODB_TEST_DATE_OUTPUT="2026-07-29T00:00:00Z"
    export MONGODB_TEST_DATASAFED_OUTPUT="TotalSize 42"

    When call run_datafile_backup_and_report

    The status should equal 1
    The line 1 of output should equal "failed with exit code 17"
    The line 2 of output should equal "tar=absent info=absent marker=present residue=0 child=$BASH_VERSION"
  End

  It "preserves existing metadata and removes temporary output when publication fails"
    export MONGODB_TEST_DATASAFED_OUTPUT="TotalSize 42"
    export MONGODB_TEST_MV_RC=29

    When call run_stat_with_existing_destination

    The status should equal 29
    The output should equal "destination=previous-metadata residue=0"
  End

  It "cleans failed publication under mongodump errexit and records action failure"
    export MONGODB_TEST_CLIENT_OUTPUT="1753747200"
    export MONGODB_TEST_DATE_OUTPUT="2026-07-29T00:00:00Z"
    export MONGODB_TEST_DATASAFED_OUTPUT="TotalSize 42"
    export MONGODB_TEST_MV_RC=29

    When call run_mongodump_publication_failure

    The status should equal 1
    The line 1 of output should equal "failed with exit code 29"
    The line 2 of output should equal "destination=previous-metadata marker=present residue=0 child=$BASH_VERSION"
  End
End
