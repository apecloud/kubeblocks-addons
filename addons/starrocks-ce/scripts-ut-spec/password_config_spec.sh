# shellcheck shell=sh

Describe "StarRocks-CE root passwordConfig"
  chart_path() {
    printf '%s' "${SHELLSPEC_CWD:?}/addons/starrocks-ce"
  }

  render_fe() {
    helm template starrocks-ce "$(chart_path)" --show-only templates/cmpd-fe.yaml
  }

  It "publishes passwordConfig on the new FE component definition"
    When call render_fe
    The status should be success
    The output should include "name: starrocks-ce-fe-1.2.0-alpha.1"
    The output should include "passwordConfig:"
    The output should not include "passwordGenerationPolicy:"
  End
End
