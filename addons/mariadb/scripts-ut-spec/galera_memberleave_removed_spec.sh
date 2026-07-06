# shellcheck shell=sh
#
# H10: the galera memberLeave action was a silent no-op — it ran in the
# kbagent execution face (no mariadb client), all SQL guarded with
# `2>/dev/null || true`, so its claimed FLUSH TABLES / wsrep_desync=ON never
# executed. Galera evicts a departed node natively (keepalive timeout) and
# the shutdown-time graceful leave (final seqno + safe_to_bootstrap, clean
# InnoDB flush) is handled by the mariadb container preStop, which runs
# in-container against 127.0.0.1. The broken action + its script were removed.

Describe "galera memberLeave removal (H10)"
  CMPD_GALERA="${SHELLSPEC_CWD:?}/addons/mariadb/templates/cmpd-galera.yaml"
  CFGMAP_GALERA="${SHELLSPEC_CWD:?}/addons/mariadb/templates/configmap-scripts-galera.yaml"
  SCRIPTS_DIR="${SHELLSPEC_CWD:?}/addons/mariadb/scripts"

  It "cmpd-galera declares no memberLeave lifecycle action"
    When run sh -c "grep -E '^[[:space:]]*memberLeave:' '${CMPD_GALERA}' || true"
    The status should be success
    The output should equal ""
  End

  It "cmpd-galera does not reference the removed galera-member-leave.sh"
    When run sh -c "grep -F 'galera-member-leave.sh' '${CMPD_GALERA}' || true"
    The status should be success
    The output should equal ""
  End

  It "galera scripts ConfigMap does not mount galera-member-leave.sh"
    When run sh -c "grep -F 'galera-member-leave.sh' '${CFGMAP_GALERA}' || true"
    The status should be success
    The output should equal ""
  End

  It "the galera-member-leave.sh script file is gone"
    When run sh -c "test ! -e '${SCRIPTS_DIR}/galera-member-leave.sh' && echo GONE"
    The status should be success
    The output should equal "GONE"
  End

  It "graceful-leave intent is still covered by the galera preStop (in-container)"
    # The shutdown-time graceful leave lives in the mariadb container preStop.
    When run sh -c "grep -c 'preStop:' '${CMPD_GALERA}'"
    The status should be success
    The output should equal "1"
  End

  It "preStop performs the in-container graceful shutdown (inline SQL or dedicated prestop script)"
    # Implementation-agnostic on purpose: the graceful shutdown may live as
    # inline preStop SQL (current main) or be delegated to a dedicated
    # galera-prestop.sh (PR #3108's bounded ordered shutdown). Pinning the
    # inline SQL literal here made this spec fail when combined with #3108
    # even though the behavior is preserved — assert the intent, not the form.
    When run sh -c "grep -F 'SET GLOBAL wsrep_on=OFF' '${CMPD_GALERA}' || grep -E 'galera-prestop\.sh' '${CMPD_GALERA}'"
    The status should be success
    The output should not equal ""
  End
End
