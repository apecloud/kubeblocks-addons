# shellcheck shell=sh

Describe "ClickHouse 26.5.3 ComponentVersion contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available

  prepare_chart() {
    tmp_chart_root=$(mktemp -d -t clickhouse-26-5-3-chart-XXXXXX)
    cp -R "$(repo_root)/addons/clickhouse" "$tmp_chart_root/clickhouse"
    cp -R "$(repo_root)/addons/kblib" "$tmp_chart_root/kblib"
    helm dependency build --skip-refresh "$tmp_chart_root/clickhouse" >/dev/null
  }

  render_component_version() {
    prepare_chart || return $?
    helm template test "$tmp_chart_root/clickhouse" --show-only templates/cmpv.yaml
  }

  count_26_5_3_compatibility_releases() {
    render_component_version | awk '
      /^[[:space:]]*- 26\.5\.3$/ { count++ }
      END { print count + 0 }
    '
  }

  cleanup_chart() {
    [ -n "${tmp_chart_root:-}" ] && rm -rf "$tmp_chart_root" 2>/dev/null || true
  }
  AfterEach 'cleanup_chart'

  It "maps every ClickHouse lifecycle image to the 26.5.3 ApeCloud image"
    When call render_component_version
    The status should be success
    The output should include "- name: 26.5.3"
    The output should include "serviceVersion: 26.5.3"
    The output should include "clickhouse: docker.io/apecloud/clickhouse:26.5.3"
    The output should include "role-probe: docker.io/apecloud/clickhouse:26.5.3"
    The output should include "switchover: docker.io/apecloud/clickhouse:26.5.3"
    The output should include "memberJoin: docker.io/apecloud/clickhouse:26.5.3"
    The output should include "memberLeave: docker.io/apecloud/clickhouse:26.5.3"
  End

  It "advertises 26.5.3 to both server and Keeper component definitions"
    When call count_26_5_3_compatibility_releases
    The status should be success
    The output should eq "2"
  End
End
