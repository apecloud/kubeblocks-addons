# shellcheck shell=sh
#
# H10: the galera memberLeave action was a silent no-op — it ran in the
# kbagent execution face (no mariadb client), all SQL guarded with
# `2>/dev/null || true`, so its claimed FLUSH TABLES / wsrep_desync=ON never
# executed. Galera evicts a departed node natively (keepalive timeout) and
# the native container preStop orders peer termination and publishes the
# watcher guard. Kubelet then signals mariadbd PID 1, which performs the
# shutdown-time graceful leave (final seqno + safe_to_bootstrap, clean InnoDB
# flush). The broken action + its script were removed.

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

  It "graceful-leave intent is still covered by the native container termination path"
    # preStop orders the nodes; kubelet TERM drives the actual engine exit.
    When run sh -c "grep -c 'preStop:' '${CMPD_GALERA}'"
    The status should be success
    The output should equal "1"
  End

  It "preStop delegates bounded ordering to the dedicated script"
    When run sh -c "grep -E 'galera-prestop\.sh' '${CMPD_GALERA}'"
    The status should be success
    The output should not equal ""
  End
End
