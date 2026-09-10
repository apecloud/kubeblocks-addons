# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey shutdown contract"
  data_cmpd="../templates/cmpd.yaml"
  sentinel_cmpd="../templates/cmpd-valkey-sentinel.yaml"
  cluster_cmpd="../templates/cmpd-valkey-cluster.yaml"

  render_addon_chart() {
    helm template review ..
  }

  data_container_has_liveness() {
    awk '
      /^      - name: valkey$/ { in_data=1; next }
      /^      - name: metrics$/ { in_data=0 }
      in_data && /livenessProbe:/ { found=1 }
      END { exit !found }
    ' "${data_cmpd}"
  }

  It "lets the Valkey PID 1 process receive Kubernetes termination directly"
    When call render_addon_chart
    The status should be success
    The stdout should not include "preStop:"
    The stdout should not include "pre-stop.sh"
  End

  It "does not package a dead custom shutdown script"
    When call test -e "../scripts/pre-stop.sh"
    The status should be failure
  End

  It "does not turn a transient data-channel failure into a business-container restart"
    When call data_container_has_liveness
    The status should be failure
  End

  It "removes PING liveness from Sentinel and Cluster containers"
    When call grep -F "livenessProbe:" "${sentinel_cmpd}" "${cluster_cmpd}"
    The status should be failure
  End

  It "keeps topology-specific readiness checks"
    When call grep -F "readinessProbe:" "${data_cmpd}" "${sentinel_cmpd}" "${cluster_cmpd}"
    The status should be success
    The stdout should include "cmpd.yaml"
    The stdout should include "cmpd-valkey-sentinel.yaml"
    The stdout should include "cmpd-valkey-cluster.yaml"
  End
End
