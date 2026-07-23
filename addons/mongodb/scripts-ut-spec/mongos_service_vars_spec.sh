# shellcheck shell=bash disable=SC2016

Describe "MongoDB mongos service variable contract"

  render_and_validate_mongos_service_vars() {
    local chart_dir

    chart_dir=${MONGODB_CHART_DIR:-$(cd .. && pwd)}
    helm dependency build "$chart_dir" >/dev/null || return
    helm template kb-addon-mongodb "$chart_dir" | ruby -ryaml -e '
      documents = YAML.load_stream($stdin.read).compact
      names = %w[mongo-config-server mongo-shard]
      mongos = documents.find do |document|
        document["kind"] == "ComponentDefinition" &&
          document.dig("metadata", "name").start_with?("mongo-mongos")
      end
      abort "missing mongo-mongos ComponentDefinition" unless mongos
      mongos_comp_def = mongos.dig("metadata", "name")

      names.each do |prefix|
        definition = documents.find do |document|
          document["kind"] == "ComponentDefinition" &&
            document.dig("metadata", "name").start_with?(prefix)
        end
        abort "missing #{prefix} ComponentDefinition" unless definition

        vars = Array(definition.dig("spec", "vars")).to_h { |item| [item["name"], item] }
        abort "#{prefix}: stale MONGOS_INTERNAL_SVC_NAME" if vars.key?("MONGOS_INTERNAL_SVC_NAME")

        host = vars.fetch("MONGOS_INTERNAL_HOST")
        port = vars.fetch("MONGOS_INTERNAL_PORT")
        { "MONGOS_INTERNAL_HOST" => host, "MONGOS_INTERNAL_PORT" => port }.each do |name, item|
          ref = item.dig("valueFrom", "serviceVarRef")
          abort "#{prefix}: #{name} is not a serviceVarRef" unless ref
          abort "#{prefix}: #{name} wrong service name" unless ref["name"] == "internal"
          abort "#{prefix}: #{name} wrong compDef" unless ref["compDef"] == mongos_comp_def
          abort "#{prefix}: #{name} must set optional:false" unless ref["optional"] == false
          abort "#{prefix}: #{name} has a direct value" if item.key?("value")
        end

        host_ref = host.dig("valueFrom", "serviceVarRef")
        abort "#{prefix}: host is not required" unless host_ref["host"] == "Required"

        port_ref = port.dig("valueFrom", "serviceVarRef")
        abort "#{prefix}: wrong port name" unless port_ref.dig("port", "name") == "mongos"
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
