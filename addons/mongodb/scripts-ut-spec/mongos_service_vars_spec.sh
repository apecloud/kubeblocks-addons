# shellcheck shell=bash disable=SC2016

Describe "MongoDB mongos service variable contract"

  render_and_validate_mongos_service_vars() {
    local chart_dir

    chart_dir=${MONGODB_CHART_DIR:-$(cd .. && pwd)}
    helm dependency build "$chart_dir" >/dev/null || return
    helm template kb-addon-mongodb "$chart_dir" | ruby -ryaml -e '
      documents = YAML.load_stream($stdin.read).compact
      names = %w[mongo-config-server mongo-shard]

      names.each do |prefix|
        definition = documents.find do |document|
          document["kind"] == "ComponentDefinition" &&
            document.dig("metadata", "name").start_with?(prefix)
        end
        abort "missing #{prefix} ComponentDefinition" unless definition

        vars = Array(definition.dig("spec", "vars")).to_h { |item| [item["name"], item] }
        abort "#{prefix}: stale MONGOS_INTERNAL_SVC_NAME" if vars.key?("MONGOS_INTERNAL_SVC_NAME")

        host = vars.fetch("MONGOS_INTERNAL_HOST")
        host_ref = host.dig("valueFrom", "serviceVarRef")
        abort "#{prefix}: MONGOS_INTERNAL_HOST is not a serviceVarRef" unless host_ref
        abort "#{prefix}: wrong service name" unless host_ref["name"] == "internal"
        abort "#{prefix}: host is not required" unless host_ref["host"] == "Required"
        abort "#{prefix}: hard-coded host value remains" if host.key?("value")

        port = vars.fetch("MONGOS_INTERNAL_PORT").dig("valueFrom", "serviceVarRef")
        abort "#{prefix}: MONGOS_INTERNAL_PORT is not a serviceVarRef" unless port
        abort "#{prefix}: wrong port name" unless port.dig("port", "name") == "mongos"
      end

      puts "mongos host and port use serviceVarRef for 2 ComponentDefinitions"
    '
  }

  It "uses the API-resolved mongos endpoint without reconstructing a DNS name"
    When call render_and_validate_mongos_service_vars
    The status should be success
    The output should include "mongos host and port use serviceVarRef for 2 ComponentDefinitions"
  End
End
