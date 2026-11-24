# shellcheck shell=bash

Describe "InfluxDB standalone selective backup and restore"
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
  bucket)
    [[ ${4:-} != missing ]] || exit 1
    ;;
  backup)
    [[ $4 != fail ]] || exit 1
    mkdir -p "$dir"
    printf '%s\0%s\0' "$2" "$4" > "$dir/manifest"
    ;;
  restore)
    printf '%s\0%s\0' "$2" "$4" | cmp - "$dir/manifest"
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

  backup_multi_buckets() {
    # Test deduplication of repeated buckets and special characters in names
    run_action backup 'selection="org1"/"raw,metrics","org1"/"roll ups/daily","org2/region,east"/"raw,metrics","org1"/"roll ups/daily"'
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Context "Backup and Restore Lifecycle"
    It "backs up multi-bucket selection and restores all by default"
      backup_multi_buckets
      expected=$(printf '%s\n' \
        '--org org1 --bucket raw,metrics' \
        '--org org1 --bucket roll ups/daily' \
        '--org org2/region,east --bucket raw,metrics')
      When call run_action restore
      The status should be success
      The contents of file "$test_dir/restored" should eq "$expected"
      The contents of file "$test_dir/info" should eq '{"totalSize":"1024"}'
    End

    It "restores filtered bucket with target rename (--new-bucket and --new-org)"
      backup_multi_buckets
      When call run_action restore 'selection="org2/region,east"/"raw,metrics"' new_bucket=target_bucket new_org=target_org
      The status should be success
      The contents of file "$test_dir/restored" should eq '--org org2/region,east --bucket raw,metrics --new-bucket target_bucket --new-org target_org'
    End

    It "restores legacy flat archive when explicit selection is provided"
      mkdir -p "$test_dir/flat"
      printf 'org1\0raw,metrics\0' > "$test_dir/flat/manifest"
      tar -C "$test_dir/flat" -cf "$test_dir/influxdb-full.tar" .
      When call run_action restore 'selection="org1"/"raw,metrics"'
      The status should be success
      The contents of file "$test_dir/restored" should eq '--org org1 --bucket raw,metrics'
    End
  End

  Context "Validation and Failure Atomicity"
    It "rejects empty selection on backup"
      When call run_action backup
      The status should be failure
      The stderr should include 'Invalid or empty InfluxDB bucket selection'
      The file "$test_dir/influxdb-full.tar" should not be exist
    End

    It "rejects malformed selection syntax"
      When call run_action backup 'selection="org1"/"unclosed,'
      The status should be failure
      The stderr should include 'Invalid or empty InfluxDB bucket selection'
      The file "$test_dir/influxdb-full.tar" should not be exist
    End

    It "fails atomically without publishing archive when a bucket backup fails"
      When call run_action backup 'selection="org1"/"roll ups/daily","org1"/"fail"'
      The status should be failure
      The file "$test_dir/influxdb-full.tar" should not be exist
      The file "$test_dir/info.exit" should be exist
    End

    It "rejects restore when a requested bucket is missing from the archive"
      backup_multi_buckets
      When call run_action restore 'selection="org1"/"roll ups/daily","org2/region,east"/"missing_bucket"'
      The status should be failure
      The stderr should include 'is missing from the backup'
      The file "$test_dir/restored" should not be exist
    End

    It "rejects restore when multiple buckets map to the same destination"
      backup_multi_buckets
      When call run_action restore new_org=target_org
      The status should be failure
      The stderr should include 'Multiple selected buckets resolve to the same destination'
      The file "$test_dir/restored" should not be exist
    End

    It "rejects restore of flat archive when selection is not specified"
      mkdir -p "$test_dir/flat"
      tar -C "$test_dir/flat" -cf "$test_dir/influxdb-full.tar" .
      When call run_action restore
      The status should be failure
      The stderr should include 'A flat archive requires an explicit bucket selection'
    End
  End
End
