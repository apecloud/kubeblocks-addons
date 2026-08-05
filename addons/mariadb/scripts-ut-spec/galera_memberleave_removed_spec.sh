# shellcheck shell=sh
#
# H10: the galera memberLeave action was a silent no-op — it ran in the
# kbagent execution face (no mariadb client), all SQL guarded with
# `2>/dev/null || true`, so its claimed FLUSH TABLES / wsrep_desync=ON never
# executed. Galera evicts a departed node natively (keepalive timeout) and
# the native container preStop orders peer termination and publishes the
# watcher guard. Kubelet then signals mariadbd PID 1, which performs the
# shutdown-time graceful leave (final seqno + safe_to_bootstrap, clean InnoDB
# flush). The broken action is removed from the new versioned CmpD, while the
# stable ConfigMap key remains as a no-op shim for alpha.26 consumers that
# still mount and invoke the historical script path.

Describe "galera memberLeave removal (H10)"
  CMPD_GALERA="${SHELLSPEC_CWD:?}/addons/mariadb/templates/cmpd-galera.yaml"
  CFGMAP_GALERA="${SHELLSPEC_CWD:?}/addons/mariadb/templates/configmap-scripts-galera.yaml"
  SCRIPTS_DIR="${SHELLSPEC_CWD:?}/addons/mariadb/scripts"
  CHART="${SHELLSPEC_CWD:?}/addons/mariadb/Chart.yaml"

  chart_alpha_at_least_27() {
    chart_version=$(awk '$1 == "version:" { print $2; exit }' "${CHART}") || return 1
    case "${chart_version}" in
      1.2.0-alpha.*) ;;
      *) return 1 ;;
    esac
    chart_alpha=${chart_version##*.}
    [ "${chart_alpha}" -ge 27 ] 2>/dev/null
  }

  It "advances the chart version so the immutable lifecycle-action change gets a new ComponentDefinition name"
    When call chart_alpha_at_least_27
    The status should be success
  End

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

  It "keeps the stable galera-member-leave.sh ConfigMap key for alpha.26 consumers"
    When run sh -c "grep -F 'galera-member-leave.sh:' '${CFGMAP_GALERA}'"
    The status should be success
    The output should not equal ""
  End

  It "ships a compatibility no-op galera-member-leave.sh"
    When run sh -c "test -f '${SCRIPTS_DIR}/galera-member-leave.sh' && grep -F 'compatibility no-op' '${SCRIPTS_DIR}/galera-member-leave.sh'"
    The status should be success
    The output should not equal ""
  End

  It "the compatibility shim cannot issue SQL or mutate wsrep state"
    When run sh -c "grep -Ev '^[[:space:]]*#' '${SCRIPTS_DIR}/galera-member-leave.sh' | grep -E 'mariadb|mysql|FLUSH TABLES|wsrep_desync' || true"
    The status should be success
    The output should equal ""
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
