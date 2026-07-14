# shellcheck shell=bash
# shellcheck disable=SC1091

Describe "StarRocks FE memberLeave"
  script="../scripts/fe-member-leave.sh"

  setup() {
    fixture_dir=$(mktemp -d)
    export fixture_dir
    export ORIGINAL_PATH="${PATH}"
    export ORIGINAL_TIMEOUT
    ORIGINAL_TIMEOUT=$(command -v timeout)
    export SCENARIO="non_leader_removed"
    export KB_LEAVE_MEMBER_POD_NAME="starrocks-fe-2"
    export FE_DISCOVERY_SERVICE_NAME="starrocks-fe-headless"
    export STARROCKS_USER="root"
    export STARROCKS_PASSWORD="secret-value"
    export MYSQL_PWD="secret-value"
    export MYSQL_COMMAND_TIMEOUT_SECS="1"
    export BDB_JE_JAR_PATH="${fixture_dir}/starrocks-bdb-je.jar"
    : > "${BDB_JE_JAR_PATH}"
    mkdir -p "${fixture_dir}/bin"
    cat > "${fixture_dir}/bin/mysql" <<'MYSQL_MOCK'
#!/usr/bin/env bash
frontend() {
  printf '%s\t%s\t%s\t8030\t9030\t9020\t%s\t12345\ttrue\ttrue\t10\t2026-07-15 00:00:00\ttrue\t\t2026-07-15 00:00:00\t3.3.0\n' \
    "$1" "$2" "$3" "$4"
}
case " $* " in
  *" SHOW FRONTENDS "*)
    count_file="${fixture_dir}/query-count"
    count=0
    [ -f "${count_file}" ] && count=$(cat "${count_file}")
    count=$((count + 1))
    printf '%s' "${count}" > "${count_file}"
    case "${SCENARIO}:${count}" in
      query_fail:1) echo "access denied for secret-value" >&2; exit 42 ;;
      query_hang:1) /bin/sleep 2 ;;
      empty_snapshot:*) : ;;
      malformed_snapshot:*) printf 'fe-0\tstarrocks-fe-0.starrocks-fe-headless\t9010\t8030\t9030\t9020\tLEADER\n' ;;
      duplicate_identity:*)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "LEADER"
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "FOLLOWER"
        ;;
      multiple_leaders:*)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "LEADER"
        frontend "fe-1" "starrocks-fe-1.starrocks-fe-headless" "9010" "LEADER"
        frontend "fe-2" "starrocks-fe-2.starrocks-fe-headless" "9010" "FOLLOWER"
        ;;
      already_absent:*)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "LEADER"
        frontend "fe-1" "starrocks-fe-1.starrocks-fe-headless" "9010" "FOLLOWER"
        ;;
      prefix_collision:*)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "LEADER"
        frontend "fe-20" "starrocks-fe-20.starrocks-fe-headless" "9010" "FOLLOWER"
        ;;
      non_leader_removed:1|alter_fail:1)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "LEADER"
        frontend "fe-1" "starrocks-fe-1.starrocks-fe-headless" "9010" "FOLLOWER"
        frontend "fe-2" "starrocks-fe-2.starrocks-fe-headless" "9010" "FOLLOWER"
        ;;
      non_leader_removed:*)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "LEADER"
        frontend "fe-1" "starrocks-fe-1.starrocks-fe-headless" "9010" "FOLLOWER"
        ;;
      leader_timeout:*|leader_transfer_fail:*)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "FOLLOWER"
        frontend "fe-1" "starrocks-fe-1.starrocks-fe-headless" "9010" "FOLLOWER"
        frontend "fe-2" "starrocks-fe-2.starrocks-fe-headless" "9010" "LEADER"
        ;;
      leader_identity_change:1)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "FOLLOWER"
        frontend "fe-1" "starrocks-fe-1.starrocks-fe-headless" "9010" "FOLLOWER"
        frontend "fe-2" "starrocks-fe-2.old-headless" "9010" "LEADER"
        ;;
      leader_identity_change:2)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "LEADER"
        frontend "fe-1" "starrocks-fe-1.starrocks-fe-headless" "9010" "FOLLOWER"
        frontend "fe-2" "starrocks-fe-2.new-headless" "9011" "FOLLOWER"
        ;;
      leader_identity_change:*)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "LEADER"
        frontend "fe-1" "starrocks-fe-1.starrocks-fe-headless" "9010" "FOLLOWER"
        ;;
      no_leader:*)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "FOLLOWER"
        frontend "fe-1" "starrocks-fe-1.starrocks-fe-headless" "9010" "FOLLOWER"
        frontend "fe-2" "starrocks-fe-2.starrocks-fe-headless" "9010" "FOLLOWER"
        ;;
      drop_still_present:*)
        frontend "fe-0" "starrocks-fe-0.starrocks-fe-headless" "9010" "LEADER"
        frontend "fe-1" "starrocks-fe-1.starrocks-fe-headless" "9010" "FOLLOWER"
        frontend "fe-2" "starrocks-fe-2.starrocks-fe-headless" "9010" "FOLLOWER"
        ;;
      *) echo "unknown scenario ${SCENARIO}:${count}" >&2; exit 99 ;;
    esac
    ;;
  *" ALTER SYSTEM DROP FOLLOWER "*)
    count_file="${fixture_dir}/alter-count"
    count=0
    [ -f "${count_file}" ] && count=$(cat "${count_file}")
    printf '%s' "$((count + 1))" > "${count_file}"
    printf '%s' "$*" > "${fixture_dir}/alter-args"
    if [ "${SCENARIO}" = "alter_fail" ]; then
      echo "ALTER rejected for secret-value" >&2
      exit 43
    fi
    ;;
  *) echo "unexpected mysql arguments" >&2; exit 98 ;;
esac
MYSQL_MOCK
    cat > "${fixture_dir}/bin/java" <<'JAVA_MOCK'
#!/usr/bin/env bash
count_file="${fixture_dir}/java-count"
count=0
[ -f "${count_file}" ] && count=$(cat "${count_file}")
printf '%s' "$((count + 1))" > "${count_file}"
if [ "${SCENARIO}" = "leader_transfer_fail" ]; then
  echo "transfer rejected for secret-value" >&2
  exit 44
fi
JAVA_MOCK
    cat > "${fixture_dir}/bin/timeout" <<'TIMEOUT_MOCK'
#!/usr/bin/env bash
if [ "${SCENARIO}" = "query_kill_timeout" ]; then
  exit 137
fi
exec "${ORIGINAL_TIMEOUT}" "$@"
TIMEOUT_MOCK
    chmod +x "${fixture_dir}/bin/mysql" "${fixture_dir}/bin/java" "${fixture_dir}/bin/timeout"
    export PATH="${fixture_dir}/bin:${PATH}"
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "${fixture_dir}"
    PATH="${ORIGINAL_PATH}"
    export PATH
    unset fixture_dir SCENARIO KB_LEAVE_MEMBER_POD_NAME
    unset FE_DISCOVERY_SERVICE_NAME STARROCKS_USER STARROCKS_PASSWORD MYSQL_PWD
    unset MYSQL_COMMAND_TIMEOUT_SECS
    unset BDB_JE_JAR_PATH ORIGINAL_PATH ORIGINAL_TIMEOUT
  }
  AfterEach "cleanup"

  run_member_leave() {
    # shellcheck source=../scripts/fe-member-leave.sh
    . "${script}"
    set +e
    member_leave
    rc=$?
    alter_count=0
    query_count=0
    alter_args=""
    [ -f "${fixture_dir}/alter-count" ] && alter_count=$(cat "${fixture_dir}/alter-count")
    [ -f "${fixture_dir}/query-count" ] && query_count=$(cat "${fixture_dir}/query-count")
    [ -f "${fixture_dir}/alter-args" ] && alter_args=$(cat "${fixture_dir}/alter-args")
    printf 'ALTER_COUNT=%s\nQUERY_COUNT=%s\nALTER_ARGS=%s\n' \
      "${alter_count}" "${query_count}" "${alter_args}"
    return "${rc}"
  }

  It "removes a non-leader and proves the exact host and edit-log port are absent"
    SCENARIO="non_leader_removed"
    When call run_member_leave
    The status should be success
    The stdout should include "member leave completed"
    The stdout should include "ALTER_COUNT=1"
    The stdout should include "QUERY_COUNT=2"
  End

  It "returns success without ALTER when the member is already absent"
    SCENARIO="already_absent"
    When call run_member_leave
    The status should be success
    The stdout should include "already removed"
    The stdout should include "ALTER_COUNT=0"
  End

  It "does not confuse a longer pod-name prefix for the leaving member"
    SCENARIO="prefix_collision"
    When call run_member_leave
    The status should be success
    The stdout should include "already removed"
    The stdout should include "ALTER_COUNT=0"
  End

  It "rejects an empty successful SHOW FRONTENDS snapshot"
    SCENARIO="empty_snapshot"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=frontends-snapshot-invalid"
    The stderr should include "retry_safe=false"
    The stdout should include "ALTER_COUNT=0"
  End

  It "rejects a malformed successful SHOW FRONTENDS snapshot"
    SCENARIO="malformed_snapshot"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=frontends-snapshot-invalid"
    The stderr should include "retry_safe=false"
    The stdout should include "ALTER_COUNT=0"
  End

  It "rejects duplicate FE identities in SHOW FRONTENDS"
    SCENARIO="duplicate_identity"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=frontends-snapshot-invalid"
    The stderr should include "retry_safe=false"
    The stdout should include "ALTER_COUNT=0"
  End

  It "rejects a SHOW FRONTENDS snapshot with multiple leaders"
    SCENARIO="multiple_leaders"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=frontends-snapshot-invalid"
    The stderr should include "retry_safe=false"
    The stdout should include "ALTER_COUNT=0"
  End

  It "fails closed when ALTER returns zero but the exact member remains"
    SCENARIO="drop_still_present"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=post-drop-membership-not-converged"
    The stderr should include "retry_safe=true"
    The stdout should not include "member leave completed"
  End

  It "fails within the configured budget when leader transfer does not converge"
    SCENARIO="leader_timeout"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=leader-transfer-not-converged"
    The stderr should include "retry_safe=true"
    The stdout should include "ALTER_COUNT=0"
    The stdout should include "QUERY_COUNT=2"
  End

  It "drops and verifies the refreshed target endpoint after leader transfer"
    SCENARIO="leader_identity_change"
    When call run_member_leave
    The status should be success
    The stdout should include "ALTER_ARGS=--connect-timeout=5 -N -B -h starrocks-fe-0.starrocks-fe-headless -P 9030 -uroot -e ALTER SYSTEM DROP FOLLOWER 'starrocks-fe-2.new-headless:9011'"
    The stdout should include "ALTER_COUNT=1"
    The stdout should include "QUERY_COUNT=3"
  End

  It "fails closed when SHOW FRONTENDS has not converged on a leader"
    SCENARIO="no_leader"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=leader-not-converged"
    The stderr should include "retry_safe=true"
    The stdout should include "ALTER_COUNT=0"
  End

  It "classifies SHOW FRONTENDS hard failure without leaking the password"
    SCENARIO="query_fail"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=query-frontends"
    The stderr should include "rc=42"
    The stderr should include "retry_safe=false"
    The stderr should not include "secret-value"
    The stdout should include "QUERY_COUNT=1"
  End

  It "kills an over-budget SHOW FRONTENDS command before the action clamp"
    SCENARIO="query_hang"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=query-frontends-timeout"
    The stderr should include "retry_safe=true"
    The stdout should include "ALTER_COUNT=0"
  End

  It "classifies timeout SIGKILL escalation as retry-safe timeout"
    SCENARIO="query_kill_timeout"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=query-frontends-timeout"
    The stderr should include "retry_safe=true"
    The stderr should include "rc=124"
    The stdout should include "ALTER_COUNT=0"
  End

  It "fails before querying when the configured BDB JE jar is unreadable"
    BDB_JE_JAR_PATH="${fixture_dir}/missing.jar"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=runtime-prerequisite"
    The stdout should include "QUERY_COUNT=0"
  End

  It "classifies ALTER hard failure without leaking the password"
    SCENARIO="alter_fail"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=drop-follower-rejected"
    The stderr should include "rc=43"
    The stderr should include "retry_safe=false"
    The stderr should not include "secret-value"
    The stdout should not include "member leave completed"
  End

  It "classifies a rejected leader transfer as operator-attention"
    SCENARIO="leader_transfer_fail"
    When call run_member_leave
    The status should be failure
    The stderr should include "phase=leader-transfer-rejected"
    The stderr should include "rc=44"
    The stderr should include "retry_safe=false"
    The stderr should not include "secret-value"
    The stdout should include "ALTER_COUNT=0"
  End
End
