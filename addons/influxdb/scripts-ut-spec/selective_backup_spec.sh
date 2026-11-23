# shellcheck shell=bash

Describe "InfluxDB selective backup and restore"
  setup() {
    test_dir=$(mktemp -d)
    scripts="${SHELLSPEC_CWD:?}/addons/influxdb/dataprotection"
    cat > "$test_dir/influx" <<'MOCK'
#!/usr/bin/env bash
set -eu
command=$1
dir=${!#}
shift
case "$command" in
  backup)
    [[ $4 != fail ]] || exit 1
    mkdir "$dir"
    printf '%s\0' "$2" "$4" > "$dir/manifest"
    ;;
  restore)
    # The selected pair must match the CLI backup staged in this directory.
    printf '%s\0' "$2" "$4" | cmp - "$dir/manifest"
    printf '%s\n' "${*:1:$#-1}" >> "$DP_BACKUP_BASE_PATH/restored"
    ;;
esac
MOCK
    cat > "$test_dir/datasafed" <<'MOCK'
#!/usr/bin/env bash
set -eu
case "$1" in
  push) cat > "$DATASAFED_BACKEND_BASE_PATH/$3" ;;
  pull) cat "$DATASAFED_BACKEND_BASE_PATH/$2" ;;
  stat) printf 'TotalSize: 1024\n' ;;
esac
MOCK
    chmod +x "$test_dir/influx" "$test_dir/datasafed"
  }

  cleanup() {
    rm -rf "$test_dir"
  }

  run_action() {
    action=$1
    shift
    cat "$scripts/common.sh" "$scripts/selection.sh" "$scripts/$action.sh" | env \
      PATH="$test_dir:$PATH" DP_DATASAFED_BIN_PATH="$test_dir" \
      DP_BACKUP_BASE_PATH="$test_dir" DP_BACKUP_INFO_FILE="$test_dir/info" \
      DP_DB_HOST=influxdb DP_DB_PASSWORD=test-token INFLUX_BACKUP_MODE=selective \
      "$@" bash
  }

  backup_multiple() {
    # A repeated selection should result in one copy of the bucket in the archive.
    run_action backup 'buckets="org1"/"raw,metrics","org1"/"roll ups/daily","org2/region,east"/"raw,metrics","org1"/"roll ups/daily"'
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  It "restores every bucket from a shared archive"
    backup_multiple
    expected=$(printf '%s\n' '--org org1 --bucket raw,metrics' '--org org1 --bucket roll ups/daily' '--org org2/region,east --bucket raw,metrics')
    When call run_action restore
    The status should be success
    The contents of file "$test_dir/restored" should eq "$expected"
    The contents of file "$test_dir/info" should eq '{"totalSize":"1024"}'
  End

  It "restores a selected bucket under a new name"
    backup_multiple
    When call run_action restore 'buckets="org2/region,east"/"raw,metrics"' new_bucket=restored new_org=target
    The status should be success
    The contents of file "$test_dir/restored" should eq '--org org2/region,east --bucket raw,metrics --new-bucket restored --new-org target'
  End

  It "rejects a missing bucket before restoring available buckets"
    backup_multiple
    When call run_action restore 'buckets="org1"/"roll ups/daily","org2/region,east"/"missing"'
    The status should be failure
    The stderr should include 'is missing from the backup'
    The file "$test_dir/restored" should not be exist
  End

  It "rejects duplicate destinations when restoring into one organization"
    backup_multiple
    When call run_action restore new_org=target
    The status should be failure
    The stderr should include 'Multiple selected buckets resolve to the same destination'
    The file "$test_dir/restored" should not be exist
  End

  It "does not publish a partial backup when a bucket fails"
    When call run_action backup 'buckets="org1"/"roll ups/daily","org1"/"fail"'
    The status should be failure
    The file "$test_dir/influxdb-full.tar" should not be exist
    The file "$test_dir/info.exit" should be exist
  End

  It "rejects malformed bucket lists before publishing a backup"
    When call run_action backup 'buckets="org1"/"rollups",'
    The status should be failure
    The stderr should include 'Invalid buckets parameter'
    The file "$test_dir/influxdb-full.tar" should not be exist
  End

  It "backs up one qualified bucket and restores it from the bucket list"
    run_action backup 'buckets="org1"/"raw,metrics"'
    When call run_action restore
    The status should be success
    The contents of file "$test_dir/restored" should eq '--org org1 --bucket raw,metrics'
  End

  It "requires buckets for selective backup"
    When call run_action backup
    The status should be failure
    The stderr should include 'Select at least one InfluxDB bucket'
    The file "$test_dir/influxdb-full.tar" should not be exist
  End

  It "restores an existing flat single-bucket archive using buckets"
    mkdir "$test_dir/flat"
    printf '%s\0' org1 raw,metrics > "$test_dir/flat/manifest"
    tar -C "$test_dir/flat" -cf "$test_dir/influxdb-full.tar" .
    When call run_action restore 'buckets="org1"/"raw,metrics"'
    The status should be success
    The contents of file "$test_dir/restored" should eq '--org org1 --bucket raw,metrics'
  End
End
