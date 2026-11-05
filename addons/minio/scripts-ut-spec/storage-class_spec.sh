# shellcheck shell=bash

Describe "MinIO storage class policy"
  Include ../scripts/storage-class.sh

  request_payload() {
    jq -cn --arg id "${2:-test-request}" --argjson parameters "$1" '{apply_request:({requestID:$id,parameters:$parameters}|tojson)}'
  }
  write_desired() { request_payload "$1" > "$MINIO_STORAGE_CLASS_FILE"; }

  setup() {
    test_dir=$(mktemp -d)
    export MINIO_JQ=$(command -v jq)
    export MINIO_STORAGE_CLASS_FILE="$test_dir/desired.json"
    export MINIO_COMP_REPLICAS=2 MINIO_COMPONENT_NAME=test-minio
    export CLUSTER_NAMESPACE=test CLUSTER_DOMAIN=cluster.local
    export MINIO_ROOT_USER=test MINIO_ROOT_PASSWORD=test-secret
    write_desired '{"standard":"EC:0","rrs":"EC:0"}'
    printf '%s' '{"standard":"EC:1","rrs":"EC:1"}' > "$test_dir/native.json"
    mock_sizes='[2]'
    fail_set=false
    mismatch=false
    fail_last_node=false
    recover_after_second_set=false
  }
  Before setup
  cleanup() { rm -rf "$test_dir"; }
  After cleanup

  minio_mc() {
    case "$*" in
      'alias set '*)
        if [[ "$fail_last_node" == true && "$4" == *test-minio-1.* ]]; then return 1; fi
        return 0 ;;
      '--json admin config get policy storage_class')
        jq -c '{status:"success",config:[{subSystem:"storage_class",kv:to_entries}]}' "$test_dir/native.json" ;;
      '--json admin info policy')
        if [[ "$recover_after_second_set" == true ]]; then
          mismatch=true
          [[ -f "$test_dir/writes" && $(wc -l < "$test_dir/writes") -ge 2 ]] && mismatch=false
        fi
        jq -cn --argjson sizes "$mock_sizes" --slurpfile native "$test_dir/native.json" --argjson mismatch "$mismatch" '
          (($sizes[0] // 2) | if . >= 8 then 4 else . / 2 | floor end) as $default |
          {info:{backend:{totalDrivesPerSet:$sizes,
            standardSCParity:(if $mismatch then 8 elif $native[0].standard == "" then $default else ($native[0].standard | ltrimstr("EC:") | tonumber) end),
            rrSCParity:(if $native[0].rrs == "" then 1 else ($native[0].rrs | ltrimstr("EC:") | tonumber) end)}}}' ;;
      'admin config set policy storage_class '*)
        echo set >> "$test_dir/writes"
        if [[ "$fail_set" == true ]]; then return 1; fi
        jq -cn --arg standard "${6#standard=}" --arg rrs "${7#rrs=}" '{standard:$standard,rrs:$rrs}' > "$test_dir/native.json" ;;
      *) return 1 ;;
    esac
  }

  It "applies the full pair once and confirms every server"
    When run apply_storage_class
    The status should be success
    The contents of file "$test_dir/writes" should eq 'set'
    The contents of file "$test_dir/native.json" should eq '{"standard":"EC:0","rrs":"EC:0"}'
  End

  It "preserves manually configured policy when no keys were supplied"
    write_desired '{}'
    When run apply_storage_class
    The status should be success
    The path "$test_dir/writes" should not be exist
  End


  It "validates without changing native or desired configuration"
    mock_sizes='[8]'
    When run apply_storage_class validate '{"standard":"EC:4","rrs":"EC:2"}'
    The status should be success
    The path "$test_dir/writes" should not be exist
    The contents of file "$test_dir/native.json" should eq '{"standard":"EC:1","rrs":"EC:1"}'
  End

  It "checks all pools instead of total replica count"
    mock_sizes='[8,2]'
    When run apply_storage_class validate '{"standard":"EC:2","rrs":"EC:1"}'
    The status should be failure
    The stderr should include 'erasure set of 2 drives'
    The path "$test_dir/writes" should not be exist
  End

  It "rejects an invalid pair before updating MinIO"
    mock_sizes='[8]'
    write_desired '{"standard":"EC:1","rrs":"EC:2"}'
    When run apply_storage_class
    The status should be failure
    The stderr should include 'STANDARD parity must not be below RRS'
    The path "$test_dir/writes" should not be exist
  End

  It "accepts native zero parity with a nonzero RRS"
    When run apply_storage_class validate '{"standard":"EC:0","rrs":"EC:1"}'
    The status should be success
  End

  It "preserves omitted keys and restores explicit empty keys to defaults"
    mock_sizes='[4]'
    write_desired '{"standard":""}'
    When run apply_storage_class
    The status should be success
    The contents of file "$test_dir/native.json" should eq '{"standard":"","rrs":"EC:1"}'
  End

  It "reads native policy instead of desired state"
    When run apply_storage_class read
    The status should be success
    The output should eq '{"standard":"EC:1","rrs":"EC:1"}'
    The path "$test_dir/writes" should not be exist
  End

  It "fails when native update fails without exposing credentials"
    fail_set=true
    When run apply_storage_class
    The status should be failure
    The stderr should eq 'MINIO_STORAGE_CLASS_ERROR: native configuration update failed'
  End

  It "does not report success when runtime has not applied the policy"
    mismatch=true
    When run apply_storage_class
    The status should be failure
    The stderr should include 'runtime policy mismatch on server 0'
  End

  It "rejects unknown keys"
    When run apply_storage_class validate '{"standard":"EC:0","typo":"EC:0"}'
    The status should be failure
    The stderr should include 'invalid desired configuration'
    The path "$test_dir/writes" should not be exist
  End

  It "rejects environment overrides before writing"
    export MINIO_STORAGE_CLASS_STANDARD=EC:1
    When run apply_storage_class
    The status should be failure
    The stderr should include 'environment overrides'
    The path "$test_dir/writes" should not be exist
  End
  It "reapplies an equal native policy to redeliver reload notifications"
    write_desired '{"standard":"EC:1","rrs":"EC:1"}'
    When run apply_storage_class
    The status should be success
    The contents of file "$test_dir/writes" should eq 'set'
  End

  It "applies distinct legal STANDARD and RRS parity"
    mock_sizes='[8]'
    write_desired '{"standard":"EC:4","rrs":"EC:2"}'
    When run apply_storage_class
    The status should be success
    The contents of file "$test_dir/native.json" should eq '{"standard":"EC:4","rrs":"EC:2"}'
  End

  It "fails closed when erasure set geometry is missing"
    mock_sizes='[]'
    When run apply_storage_class
    The status should be failure
    The stderr should include 'missing or invalid erasure set geometry'
    The path "$test_dir/writes" should not be exist
  End

  It "requires confirmation from every server"
    fail_last_node=true
    When run apply_storage_class
    The status should be failure
    The stderr should include 'cannot connect to server 1'
  End

  It "checks the first pool's effective default against later smaller sets"
    mock_sizes='[8,4]'
    When run apply_storage_class validate '{"standard":"","rrs":""}'
    The status should be failure
    The stderr should include 'erasure set of 4 drives'
    The path "$test_dir/writes" should not be exist
  End

  It "recovers when a prior set persisted but its runtime reload failed"
    recover_after_second_set=true
    retry_apply() {
      apply_storage_class 2> "$test_dir/first-error"
      local first_status=$?
      [[ "$first_status" != 0 ]] || return 1
      [[ $(cat "$test_dir/native.json") == '{"standard":"EC:0","rrs":"EC:0"}' ]] || return 1
      apply_storage_class
    }
    When run retry_apply
    The status should be success
    The contents of file "$test_dir/first-error" should include 'runtime policy mismatch on server 0'
    The contents of file "$test_dir/writes" should eq "$(printf 'set\nset')"
  End

  It "uses synchronous reload input even while the mounted file is stale"
    write_desired '{}'
    Data "$(request_payload '{"standard":"EC:0","rrs":"EC:0"}')"
    When run apply_storage_class apply-stdin
    The status should be success
    The contents of file "$test_dir/native.json" should eq '{"standard":"EC:0","rrs":"EC:0"}'
    The contents of file "$test_dir/writes" should eq 'set'
  End

  It "preserves empty values and merges unchanged native keys from reload input"
    mock_sizes='[4]'
    Data "$(request_payload '{"standard":""}')"
    When run apply_storage_class apply-stdin
    The status should be success
    The contents of file "$test_dir/native.json" should eq '{"standard":"","rrs":"EC:1"}'
  End

  It "keeps the full requested pair despite mixed native and managed drift"
    write_desired '{"standard":"EC:1","rrs":"EC:1"}'
    echo '{"standard":"EC:0","rrs":"EC:1"}' > "$test_dir/native.json"
    Data "$(request_payload '{"standard":"EC:1","rrs":"EC:0"}')"
    When run apply_storage_class apply-stdin
    The status should be success
    The contents of file "$test_dir/native.json" should eq '{"standard":"EC:1","rrs":"EC:0"}'
  End

  It "merges a queued partial request with native state at execution time"
    write_desired '{"standard":"EC:0","rrs":"EC:0"}'
    echo '{"standard":"EC:1","rrs":"EC:1"}' > "$test_dir/native.json"
    Data "$(request_payload '{"rrs":"EC:0"}')"
    When run apply_storage_class apply-stdin
    The status should be success
    The contents of file "$test_dir/native.json" should eq '{"standard":"EC:1","rrs":"EC:0"}'
  End

  It "rejects malformed envelopes before updating MinIO"
    Data '{"apply_request":"{\"requestID\":\"\",\"parameters\":{}}"}'
    When run apply_storage_class apply-stdin
    The status should be failure
    The stderr should include 'invalid storage class request'
    The path "$test_dir/writes" should not be exist
  End

End
