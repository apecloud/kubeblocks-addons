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

custom_zookeeper_binding_is_rendered() {
  local rendered
  rendered=$(render_clickhouse_cluster \
    --namespace clickhouse-ns \
    --set mode=withZookeeper \
    --set-string zookeeper.primary.namespace=zookeeper-ns \
    --set-string zookeeper.primary.cluster=zookeeper-main \
    --set-string zookeeper.primary.component=coordination \
    --set-string zookeeper.primary.service=zookeeper-client \
    --set-string zookeeper.primary.port=custom-client \
    --set-string 'zookeeper.auxiliary[0].namespace=zookeeper-aux-ns' \
    --set-string 'zookeeper.auxiliary[0].cluster=zookeeper-aux' \
    --set-string 'zookeeper.auxiliary[0].component=aux-coordination' \
    --set-string 'zookeeper.auxiliary[0].service=aux-client' \
    --set-string 'zookeeper.auxiliary[0].port=aux-custom-client') || return

  local expected
  for expected in \
    'namespace: "zookeeper-ns"' \
    'cluster: "zookeeper-main"' \
    'component: "coordination"' \
    'service: "zookeeper-client"' \
    'port: "custom-client"' \
    'namespace: "zookeeper-aux-ns"' \
    'cluster: "zookeeper-aux"' \
    'component: "aux-coordination"' \
    'service: "aux-client"' \
    'port: "aux-custom-client"'; do
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

  grep -Fq -- '- name: CLICKHOUSE_ZOOKEEPER_SERVICE' <<<"$component" || return 1
  grep -Fq -- '- name: CLICKHOUSE_AUX_ZOOKEEPER_1_SERVICE' <<<"$component" || return 1
  grep -Fq -- 'splitList "," .CLICKHOUSE_ZOOKEEPER_SERVICE' <<<"$config" || return 1
  grep -Fq -- 'printf "CLICKHOUSE_AUX_ZOOKEEPER_%d_SERVICE"' <<<"$config" || return 1
  ! grep -Fq -- 'ZOOKEEPER_POD_FQDNS' <<<"$component"
}

Describe "ClickHouse external ZooKeeper ServiceRef contract"
  It "rejects withZookeeper mode without a primary cluster"
    When call render_with_zookeeper_without_primary
    The status should be failure
    The output should include "/zookeeper/primary/cluster"
  End

  It "renders the configured ZooKeeper service and port selectors"
    When call custom_zookeeper_binding_is_rendered
    The status should be success
  End

  It "preserves the existing ClickHouse resource defaults"
    When call default_clickhouse_resources_are_unchanged
    The status should be success
  End

  It "uses the selected ZooKeeper service endpoints in ClickHouse configuration"
    When call zookeeper_service_endpoints_are_consumed
    The status should be success
  End
End
