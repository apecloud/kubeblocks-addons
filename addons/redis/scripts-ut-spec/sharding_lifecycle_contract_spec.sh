# shellcheck shell=sh

Describe "Redis sharding lifecycle contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/redis" "$(repo_root)"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available

  render_sharding_definition() {
    helm template test "$(chart_path)" \
      --show-only templates/shardingdefinition.yaml
  }

  It "allows the same-name ShardingDefinition lifecycle spec to upgrade"
    When call render_sharding_definition
    The status should be success
    The output should include 'apps.kubeblocks.io/skip-immutable-check: "true"'
  End
End
