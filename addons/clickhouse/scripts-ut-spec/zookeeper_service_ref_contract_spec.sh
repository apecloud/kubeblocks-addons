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
End
