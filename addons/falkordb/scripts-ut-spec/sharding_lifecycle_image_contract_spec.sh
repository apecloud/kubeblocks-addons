# shellcheck shell=sh

Describe "FalkorDB sharding lifecycle image contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/falkordb" "$(repo_root)"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available

  render_sharding_definition() {
    tmp_render=$(mktemp -t falkordb-sharding-render-XXXXXX)
    helm template test "$(chart_path)" >"$tmp_render" || return $?
    awk '
      capture && /^---$/ { exit }
      $0 == "kind: ShardingDefinition" { capture = 1 }
      capture { print }
    ' "$tmp_render"
  }

  render_cluster_component_version() {
    tmp_render=$(mktemp -t falkordb-cluster-version-render-XXXXXX)
    helm template test "$(chart_path)" \
      --show-only templates/cmpv-falkordb-cluster.yaml >"$tmp_render" || return $?
    cat "$tmp_render"
  }

  cleanup_render() {
    [ -n "${tmp_render:-}" ] && rm -f "$tmp_render" 2>/dev/null || true
  }
  AfterEach 'cleanup_render'

  It "shares FalkorDB container resources without a custom exec image"
    When call render_sharding_definition
    The status should be success
    The output should include "container: falkordb-cluster"
    The output should not include "image:"
  End

  It "keeps lifecycle action images versioned by ComponentVersion"
    When call render_cluster_component_version
    The status should be success
    The output should include "serviceVersion: 4.12.5"
    The output should include "postProvision: docker.io/falkordb/falkordb:v4.12.5"
    The output should include "serviceVersion: 4.14.12"
    The output should include "postProvision: docker.io/falkordb/falkordb:v4.14.12"
  End
End
