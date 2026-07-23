# shellcheck shell=bash

Describe "MongoDB sharding topology provision order"

  verify_sharding_provision_order() {
    local chart_dir rendered render_rc

    chart_dir=$(cd .. && pwd)
    rendered=$(helm template kb-addon-mongodb "$chart_dir" --dependency-update)
    render_rc=$?
    if [ "$render_rc" -ne 0 ]; then
      echo "helm template failed with status $render_rc" >&2
      return "$render_rc"
    fi

    # shellcheck disable=SC2016
    printf '%s\n' "$rendered" | ruby -ryaml -e '
      documents = YAML.load_stream($stdin.read).compact
      definitions = documents.select do |document|
        document["kind"] == "ClusterDefinition" &&
          document.dig("metadata", "name") == "mongodb"
      end
      abort "expected one MongoDB ClusterDefinition, got #{definitions.length}" unless definitions.length == 1

      topologies = definitions.first.dig("spec", "topologies") || []
      shardings = topologies.select { |topology| topology["name"] == "sharding" }
      abort "expected one MongoDB sharding topology, got #{shardings.length}" unless shardings.length == 1
      sharding = shardings.first

      component_names = (sharding["components"] || []).map { |component| component["name"] }
      sharding_names = (sharding["shardings"] || []).map { |entry| entry["name"] }
      expected_members = ["config-server", "mongos", "shard"]
      actual_members = (component_names + sharding_names).sort
      abort "unexpected sharding members: #{actual_members.inspect}" unless actual_members == expected_members.sort

      expected_order = ["config-server", "mongos", "shard"]
      actual_order = sharding.dig("orders", "provision")
      abort "expected provision order #{expected_order.inspect}, got #{actual_order.inspect}" unless actual_order == expected_order

      expected_terminate = ["shard", "mongos,config-server"]
      actual_terminate = sharding.dig("orders", "terminate")
      abort "expected terminate order #{expected_terminate.inspect}, got #{actual_terminate.inspect}" unless actual_terminate == expected_terminate

      expected_update = ["mongos,config-server", "shard"]
      actual_update = sharding.dig("orders", "update")
      abort "expected update order #{expected_update.inspect}, got #{actual_update.inspect}" unless actual_update == expected_update
    '
  }

  verify_renderer_failure_is_propagated() {
    local fake_bin test_status

    fake_bin=$(mktemp -d)
    cat > "$fake_bin/helm" <<'FAKE_HELM'
#!/bin/sh
cat <<'YAML'
apiVersion: apps.kubeblocks.io/v1
kind: ClusterDefinition
metadata:
  name: mongodb
spec:
  topologies:
    - name: sharding
      components:
        - name: mongos
        - name: config-server
      shardings:
        - name: shard
      orders:
        provision:
          - config-server
          - mongos
          - shard
        terminate:
          - shard
          - mongos,config-server
        update:
          - mongos,config-server
          - shard
YAML
exit 42
FAKE_HELM
    chmod +x "$fake_bin/helm"

    PATH="$fake_bin:$PATH" verify_sharding_provision_order
    test_status=$?
    rm -rf "$fake_bin"
    return "$test_status"
  }

  verify_duplicate_sharding_topology_is_rejected() {
    local fake_bin test_status

    fake_bin=$(mktemp -d)
    cat > "$fake_bin/helm" <<'FAKE_HELM'
#!/bin/sh
cat <<'YAML'
apiVersion: apps.kubeblocks.io/v1
kind: ClusterDefinition
metadata:
  name: mongodb
spec:
  topologies:
    - name: sharding
      components:
        - name: mongos
        - name: config-server
      shardings:
        - name: shard
      orders:
        provision:
          - config-server
          - mongos
          - shard
        terminate:
          - shard
          - mongos,config-server
        update:
          - mongos,config-server
          - shard
    - name: sharding
      components:
        - name: unexpected
      orders:
        provision:
          - unexpected
YAML
FAKE_HELM
    chmod +x "$fake_bin/helm"

    PATH="$fake_bin:$PATH" verify_sharding_provision_order
    test_status=$?
    rm -rf "$fake_bin"
    return "$test_status"
  }

  It "provisions config server, mongos, then shards"
    When call verify_sharding_provision_order
    The status should be success
  End

  It "propagates a renderer failure after valid output"
    When call verify_renderer_failure_is_propagated
    The stderr should include "helm template failed with status 42"
    The status should equal 42
  End

  It "rejects duplicate sharding topologies"
    When call verify_duplicate_sharding_topology_is_rejected
    The stderr should include "expected one MongoDB sharding topology, got 2"
    The status should be failure
  End
End
