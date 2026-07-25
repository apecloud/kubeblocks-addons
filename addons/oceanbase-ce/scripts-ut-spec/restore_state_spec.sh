# shellcheck shell=bash

Describe "OceanBase CE restore durable no-replay state"
  Include ../dataprotection/restore-state.sh

  set_restore_identity() {
    KB_DP_RESTORE_NAMESPACE="default"
    KB_DP_RESTORE_NAME="restore-a"
    KB_DP_RESTORE_UID="11111111-2222-3333-4444-555555555555"
    KB_DP_RESTORE_ACTION="postReady"
    KB_DP_RESTORE_ACTION_ORDINAL="0"
    KB_DP_AUTHORIZATION_GENERATION="1"
    KB_DP_AUTHORIZATION_NONCE="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    KB_DP_JOB_NAME="restore-post-ready"
    KB_DP_JOB_UID="66666666-7777-8888-9999-000000000000"
    KB_DP_POD_NAME="restore-a-pod"
    KB_DP_POD_UID="bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
    KB_DP_RESTORE_IDENTITY_SHA=$(
      printf '%s\0%s\0%s\0%s\0%s' \
        "$KB_DP_RESTORE_UID" \
        "$KB_DP_RESTORE_NAMESPACE" \
        "$KB_DP_RESTORE_NAME" \
        "$KB_DP_RESTORE_ACTION" \
        "$KB_DP_RESTORE_ACTION_ORDINAL" |
        restore_state_sha256
    )
    export KB_DP_RESTORE_NAMESPACE KB_DP_RESTORE_NAME KB_DP_RESTORE_UID
    export KB_DP_RESTORE_ACTION KB_DP_RESTORE_ACTION_ORDINAL
    export KB_DP_AUTHORIZATION_GENERATION KB_DP_AUTHORIZATION_NONCE
    export KB_DP_JOB_NAME KB_DP_JOB_UID KB_DP_POD_NAME KB_DP_POD_UID
    export KB_DP_RESTORE_IDENTITY_SHA
  }

  BeforeEach 'set_restore_identity'

  It "rejects a missing exact identity field"
    unset KB_DP_RESTORE_UID
    When call restore_state_validate_identity
    The status should be failure
    The stderr should include "missing restore identity env KB_DP_RESTORE_UID"
  End

  It "rejects a mismatched canonical identity SHA"
    KB_DP_RESTORE_IDENTITY_SHA="deadbeef"
    When call restore_state_validate_identity
    The status should be failure
    The stderr should include "restore identity SHA mismatch"
  End

  It "treats RESTORE status with a NULL role as observer-only"
    When call restore_state_classify_tenant "RESTORE" "NULL"
    The output should eq "OBSERVE"
    The status should be success
  End

  It "allows one dispatch and makes a retry observer-only"
    state_root=$(mktemp -d)
    KB_DP_RESTORE_STATE_ROOT="$state_root"
    export KB_DP_RESTORE_STATE_ROOT

    first_rc=0
    second_rc=0
    restore_state_claim_dispatch "tenant-a" || first_rc=$?
    restore_state_claim_dispatch "tenant-a" || second_rc=$?

    When call printf '%s %s' "$first_rc" "$second_rc"
    The output should eq "0 10"
    The status should be success
    rm -rf "$state_root"
  End

  It "rejects a different authorization nonce for an existing tenant intent"
    state_root=$(mktemp -d)
    KB_DP_RESTORE_STATE_ROOT="$state_root"
    export KB_DP_RESTORE_STATE_ROOT
    restore_state_claim_dispatch "tenant-a"
    KB_DP_AUTHORIZATION_NONCE="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

    When call restore_state_claim_dispatch "tenant-a"
    The status should be failure
    The stderr should include "restore intent identity mismatch"
    rm -rf "$state_root"
  End

  It "times out without canonical mutation while a live installer lock is held"
    state_root=$(mktemp -d)
    KB_DP_RESTORE_STATE_ROOT="$state_root"
    export KB_DP_RESTORE_STATE_ROOT
    action_root="${state_root}/${KB_DP_RESTORE_IDENTITY_SHA}"
    mkdir -p "$action_root"
    mkdir "${action_root}/installer.lock.held"
    sleep() { :; }

    When call restore_state_claim_dispatch "tenant-a"
    The status should eq 11
    The path "${action_root}/tenants" should not be exist
    The path "${action_root}/executions/${KB_DP_JOB_UID}/${KB_DP_POD_UID}/terminal" should be file
    rm -rf "$state_root"
  End

  It "contains exactly one ALTER execution site and no in-function retry loop"
    restore_function=$(
      awk '
        /^function restoreTenant[(][)]/ { in_function=1 }
        in_function { print }
        in_function && /^}/ { exit }
      ' ../dataprotection/restore.sh
    )
    # shellcheck disable=SC2016
    mutation_sites=$(printf '%s\n' "$restore_function" | grep -Fc '${mysql_cmd} "${sql}"')
    retry_loops=$(printf '%s\n' "$restore_function" | grep -Ec 'while[[:space:]]+true|time=[$][(][(]time[+]1[)][)]' || true)

    When call printf '%s %s' "$mutation_sites" "$retry_loops"
    The output should eq "1 0"
    The status should be success
  End

  It "fails closed when a no-replay intent is not yet observable"
    observer_branch=$(
      awk '
        /^[[:space:]]*10[)]/ { in_branch=1 }
        in_branch { print }
        in_branch && /^[[:space:]]*;;/ { exit }
      ' ../dataprotection/restore.sh
    )
    exit_count=$(printf '%s\n' "$observer_branch" | grep -Ec '^[[:space:]]*exit 1$' || true)
    continue_count=$(printf '%s\n' "$observer_branch" | grep -Ec '^[[:space:]]*continue$' || true)

    When call printf '%s %s' "$exit_count" "$continue_count"
    The output should eq "1 0"
    The status should be success
  End
End
