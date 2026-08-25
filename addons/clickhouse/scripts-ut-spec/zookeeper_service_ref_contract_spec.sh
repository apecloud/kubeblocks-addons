# shellcheck shell=bash
# shellcheck disable=SC2034

cluster_chart_dir="../../../addons-cluster/clickhouse"

render_clickhouse_cluster() {
  helm dependency build --skip-refresh "$cluster_chart_dir" >/dev/null || return
  helm template clickhouse "$cluster_chart_dir" --show-only templates/cluster.yaml "$@"
}

render_with_zookeeper_without_primary() {
  render_clickhouse_cluster --set mode=withZookeeper 2>&1
}

# Helm renders the schema violation either as a JSON pointer
# ('/zookeeper/primary/cluster') or a dotted path
# ('zookeeper.primary.cluster') depending on the Helm version.
# shellspec passes the output via stdin to `should satisfy` predicates.
output_mentions_zookeeper_primary_cluster() {
  local output
  output=$(cat)
  case "$output" in
    *zookeeper.primary.cluster* | *zookeeper/primary/cluster*) return 0 ;;
  esac
  return 1
}

custom_zookeeper_binding_is_rendered() {
  local rendered
  rendered=$(render_clickhouse_cluster \
    --namespace clickhouse-ns \
    --set mode=withZookeeper \
    --set-string zookeeper.primary.namespace=zookeeper-ns \
    --set-string zookeeper.primary.cluster=zookeeper-main \
    --set-string zookeeper.primary.component=coordination \
    --set-string 'zookeeper.auxiliary[0].namespace=zookeeper-aux-ns' \
    --set-string 'zookeeper.auxiliary[0].cluster=zookeeper-aux' \
    --set-string 'zookeeper.auxiliary[0].component=aux-coordination') || return

  local expected
  for expected in \
    'namespace: "zookeeper-ns"' \
    'cluster: "zookeeper-main"' \
    'component: coordination' \
    'namespace: "zookeeper-aux-ns"' \
    'cluster: "zookeeper-aux"' \
    'component: aux-coordination'; do
    grep -Fq -- "$expected" <<<"$rendered" || return 1
  done
}

default_clickhouse_resources_are_unchanged() {
  local rendered
  rendered=$(render_clickhouse_cluster --set mode=standalone) || return

  [[ $(grep -Fc 'cpu: "1"' <<<"$rendered") -eq 2 ]] || return 1
  [[ $(grep -Fc 'memory: "2Gi"' <<<"$rendered") -eq 2 ]] || return 1
  ! grep -Fq 'memory: "1Gi"' <<<"$rendered"
}

zookeeper_service_endpoints_are_consumed() {
  local component config
  component=$(helm template clickhouse .. --show-only templates/cmpd-ch.yaml) || return
  config=$(helm template clickhouse .. --show-only templates/config-template.yaml) || return

  grep -Fq -- '- name: CLICKHOUSE_ZOOKEEPER_POD_FQDNS' <<<"$component" || return 1
  grep -Fq -- '- name: CLICKHOUSE_AUX_ZOOKEEPER_1_POD_FQDNS' <<<"$component" || return 1
  grep -Fq -- 'splitList "," .CLICKHOUSE_ZOOKEEPER_POD_FQDNS' <<<"$config" || return 1
  grep -Fq -- 'printf "CLICKHOUSE_AUX_ZOOKEEPER_%d_POD_FQDNS"' <<<"$config" || return 1
}

clickhouse_22_component_definition_is_rendered() {
  helm dependency build --skip-refresh .. >/dev/null || return
  local cmpd
  cmpd=$(helm template clickhouse .. --show-only templates/cmpd-ch-22.yaml) || return

  grep -Fq -- 'name: clickhouse-22-1.2.0-alpha.1' <<<"$cmpd" || return 1
  grep -Fq -- '- name: copy-keeper-client' <<<"$cmpd" || return 1
  grep -Fq -- '/shared-tools/clickhouse-keeper-client' <<<"$cmpd" || return 1
  grep -Fq -- '^clickhouse-22-1.*' <<<"$cmpd" || return 1
}

keeper_22_component_definition_is_rendered() {
  helm dependency build --skip-refresh .. >/dev/null || return
  local cmpd
  cmpd=$(helm template clickhouse .. --show-only templates/cmpd-keeper-22.yaml) || return

  grep -Fq -- 'name: clickhouse-keeper-22-1.2.0-alpha.1' <<<"$cmpd" || return 1
  grep -Fq -- '- name: copy-keeper-client' <<<"$cmpd" || return 1
  grep -Fq -- '/shared-tools/clickhouse-keeper-client' <<<"$cmpd" || return 1
}

zk_init_only_compatible_with_legacy_versions() {
  helm dependency build --skip-refresh .. >/dev/null || return
  local cmpv
  cmpv=$(helm template clickhouse .. --show-only templates/cmpv.yaml) || return

  # The clickhouse-22 and clickhouse-keeper-22 compDefs must be listed only for
  # 22.x and earlier releases. Extract each legacy block from its "# Legacy
  # versions" comment up to and including its own compDef line.
  local blocks
  blocks=$(awk '
    /^[[:space:]]*# Legacy versions/ { capture=1; buf=""; next }
    capture {
      buf = buf $0 "\n"
      if (/^[[:space:]]*- \^clickhouse-(22|keeper-22)-1\.\*/) {
        printf "%s", buf
        capture=0
      }
    }
  ' <<<"$cmpv") || return 1
  grep -Fq -- '^clickhouse-22-1.*' <<<"$blocks" || return 1
  grep -Fq -- '^clickhouse-keeper-22-1.*' <<<"$blocks" || return 1
  grep -Fq -- '22.8.21' <<<"$blocks" || return 1
  ! grep -Fq -- '25.9.7' <<<"$blocks"
}

legacy_with_zookeeper_uses_22_cmpd() {
  helm dependency build --skip-refresh "$cluster_chart_dir" >/dev/null || return
  local rendered
  rendered=$(render_clickhouse_cluster \
    --set mode=withZookeeper \
    --set version=22.8.21 \
    --set-string zookeeper.primary.cluster=zookeeper-main) || return

  grep -Fq -- 'componentDef: clickhouse-22-1' <<<"$rendered" || return 1
  ! grep -Fq -- 'componentDef: clickhouse-1' <<<"$rendered"
}

modern_with_zookeeper_uses_plain_cmpd() {
  helm dependency build --skip-refresh "$cluster_chart_dir" >/dev/null || return
  local rendered
  rendered=$(render_clickhouse_cluster \
    --set mode=withZookeeper \
    --set version=25.9.7 \
    --set-string zookeeper.primary.cluster=zookeeper-main) || return

  grep -Fq -- 'componentDef: clickhouse-1' <<<"$rendered" || return 1
  ! grep -Fq -- 'componentDef: clickhouse-22-1' <<<"$rendered"
}

cluster_mode_uses_22_cmpd_for_legacy() {
  helm dependency build --skip-refresh "$cluster_chart_dir" >/dev/null || return
  local rendered
  rendered=$(render_clickhouse_cluster \
    --set mode=cluster \
    --set version=22.8.21) || return

  grep -Fq -- 'componentDef: clickhouse-22-1' <<<"$rendered" || return 1
  ! grep -Fq -- 'componentDef: clickhouse-1' <<<"$rendered"
}

cluster_mode_uses_keeper_22_for_legacy() {
  helm dependency build --skip-refresh "$cluster_chart_dir" >/dev/null || return
  local rendered
  rendered=$(render_clickhouse_cluster \
    --set mode=cluster \
    --set version=22.8.21) || return

  grep -Fq -- 'componentDef: clickhouse-keeper-22-1' <<<"$rendered" || return 1
  ! grep -Fq -- 'componentDef: clickhouse-keeper-1' <<<"$rendered"
}

cluster_mode_uses_plain_keeper_for_modern() {
  helm dependency build --skip-refresh "$cluster_chart_dir" >/dev/null || return
  local rendered
  rendered=$(render_clickhouse_cluster \
    --set mode=cluster \
    --set version=25.9.7) || return

  grep -Fq -- 'componentDef: clickhouse-keeper-1' <<<"$rendered" || return 1
  ! grep -Fq -- 'componentDef: clickhouse-keeper-22-1' <<<"$rendered"
}

Describe "ClickHouse external ZooKeeper ServiceRef contract"
  It "rejects withZookeeper mode without a primary cluster"
    When call render_with_zookeeper_without_primary
    The status should be failure
    The output should satisfy output_mentions_zookeeper_primary_cluster
  End

  It "renders the configured ZooKeeper cluster binding with pod FQDN selectors"
    When call custom_zookeeper_binding_is_rendered
    The status should be success
  End

  It "preserves the existing ClickHouse resource defaults"
    When call default_clickhouse_resources_are_unchanged
    The status should be success
  End

  It "uses the ZooKeeper pod FQDNs in ClickHouse configuration"
    When call zookeeper_service_endpoints_are_consumed
    The status should be success
  End

  It "renders the clickhouse-22 ComponentDefinition with a copy-keeper-client initContainer"
    When call clickhouse_22_component_definition_is_rendered
    The status should be success
  End

  It "renders the clickhouse-keeper-22 ComponentDefinition with a copy-keeper-client initContainer"
    When call keeper_22_component_definition_is_rendered
    The status should be success
  End

  It "limits clickhouse-22 and clickhouse-keeper-22 compatibility to legacy (22.x and earlier) releases"
    When call zk_init_only_compatible_with_legacy_versions
    The status should be success
  End

  It "selects clickhouse-22 for legacy versions in withZookeeper mode"
    When call legacy_with_zookeeper_uses_22_cmpd
    The status should be success
  End

  It "keeps clickhouse-1 for modern versions in withZookeeper mode"
    When call modern_with_zookeeper_uses_plain_cmpd
    The status should be success
  End

  It "selects clickhouse-22 for legacy versions in cluster mode"
    When call cluster_mode_uses_22_cmpd_for_legacy
    The status should be success
  End

  It "selects clickhouse-keeper-22 for legacy versions in cluster mode"
    When call cluster_mode_uses_keeper_22_for_legacy
    The status should be success
  End

  It "keeps clickhouse-keeper-1 for modern versions in cluster mode"
    When call cluster_mode_uses_plain_keeper_for_modern
    The status should be success
  End
End
