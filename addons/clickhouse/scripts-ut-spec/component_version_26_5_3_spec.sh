# shellcheck shell=sh

Describe "ClickHouse 26.5.3 ComponentVersion contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available

  prepare_addon_chart() {
    tmp_addon_chart_root=$(mktemp -d -t clickhouse-26-5-3-addon-chart-XXXXXX)
    cp -R "$(repo_root)/addons/clickhouse" "$tmp_addon_chart_root/clickhouse"
    cp -R "$(repo_root)/addons/kblib" "$tmp_addon_chart_root/kblib"
    helm dependency build --skip-refresh "$tmp_addon_chart_root/clickhouse" >/dev/null
  }

  prepare_cluster_chart() {
    tmp_cluster_chart_root=$(mktemp -d -t clickhouse-26-5-3-cluster-chart-XXXXXX)
    cp -R "$(repo_root)/addons-cluster/clickhouse" "$tmp_cluster_chart_root/clickhouse"
    cp -R "$(repo_root)/addons-cluster/kblib" "$tmp_cluster_chart_root/kblib"
    helm dependency build --skip-refresh "$tmp_cluster_chart_root/clickhouse" >/dev/null
  }

  render_component_version() {
    prepare_addon_chart || return $?
    helm template test "$tmp_addon_chart_root/clickhouse" --show-only templates/cmpv.yaml
  }

  render_component_definitions() {
    prepare_addon_chart || return $?
    helm template test "$tmp_addon_chart_root/clickhouse" \
      --show-only templates/cmpd-ch.yaml \
      --show-only templates/cmpd-keeper.yaml
  }

  render_ops_definitions() {
    prepare_addon_chart || return $?
    helm template test "$tmp_addon_chart_root/clickhouse" \
      --show-only templates/opsdefinition.yaml
  }

  render_cluster() {
    prepare_cluster_chart || return $?
    helm template test "$tmp_cluster_chart_root/clickhouse" \
      --show-only templates/cluster.yaml \
      "$@"
  }

  count_26_5_3_compatibility_releases() {
    render_component_version | awk '
      /^[[:space:]]*- 26\.5\.3$/ { count++ }
      END { print count + 0 }
    '
  }

  cleanup_chart() {
    [ -n "${tmp_addon_chart_root:-}" ] && rm -rf "$tmp_addon_chart_root" 2>/dev/null || true
    [ -n "${tmp_cluster_chart_root:-}" ] && rm -rf "$tmp_cluster_chart_root" 2>/dev/null || true
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

  It "keeps both ComponentDefinition defaults on 25.9.7"
    When call render_component_definitions
    The status should be success
    The output should include "name: clickhouse-1"
    The output should include "name: clickhouse-keeper-1"
    The output should include "serviceVersion: 25.9.7"
    The output should not include "serviceVersion: 26.5.3"
    The output should satisfy awk '
      /^[[:space:]]*serviceVersion: 25\.9\.7$/ { count++ }
      END { exit count == 2 ? 0 : 1 }
    '
  End

  It "keeps the cluster chart default explicit on 25.9.7"
    When call render_cluster
    The status should be success
    The output should include "name: ch-keeper"
    The output should include "name: clickhouse"
    The output should not include "serviceVersion: 26.5.3"
    The output should satisfy awk '
      /^[[:space:]]*serviceVersion: 25\.9\.7$/ { count++ }
      /^[[:space:]]*serviceVersion:[[:space:]]*$/ { blank++ }
      END { exit count == 2 && blank == 0 ? 0 : 1 }
    '
  End

  It "renders both cluster components on 26.5.3 only when explicitly selected"
    When call render_cluster --set version=26.5.3
    The status should be success
    The output should not include "serviceVersion: 25.9.7"
    The output should satisfy awk '
      /^[[:space:]]*serviceVersion: 26\.5\.3$/ { count++ }
      END { exit count == 2 ? 0 : 1 }
    '
  End

  It "keeps both OpsDefinition job images on the bounded 25.9.7 tool version"
    When call render_ops_definitions
    The status should be success
    The output should include "name: post-rebuild-for-clickhouse"
    The output should include "name: post-scale-out-shard-for-clickhouse"
    The output should not include "docker.io/apecloud/clickhouse:26.5.3"
    The output should satisfy awk '
      /^[[:space:]]*image: docker\.io\/apecloud\/clickhouse:25\.9\.7$/ { count++ }
      END { exit count == 2 ? 0 : 1 }
    '
  End
End
