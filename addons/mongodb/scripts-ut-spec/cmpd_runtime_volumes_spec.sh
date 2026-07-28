# shellcheck shell=bash

Describe "MongoDB ComponentDefinition runtime volumes render contract"

  validate_runtime_volumes() {
    local mode="$1"
    local chart_dir
    local -a helm_args

    chart_dir=$(cd .. && pwd)
    helm_args=(template kb-addon-mongodb "$chart_dir" --dependency-update)
    if [[ "$mode" == "enabled" ]]; then
      helm_args+=(--set logCollector.enabled=true)
    fi

    helm "${helm_args[@]}" | ruby -ryaml -e '
      documents = YAML.load_stream($stdin.read).compact
      component_definitions = documents.select { |doc| doc["kind"] == "ComponentDefinition" }
      patterns = {
        "config-server" => /^mongo-config-server-/,
        "shard" => /^mongo-shard-/,
        "mongos" => /^mongo-mongos-/,
        "mongodb" => /^mongodb-/
      }

      definitions = patterns.to_h do |role, pattern|
        matches = component_definitions.select do |doc|
          doc.dig("metadata", "name")&.match?(pattern)
        end
        abort "expected one #{role} ComponentDefinition, got #{matches.length}" unless matches.length == 1
        [role, matches.first]
      end

      definitions.each do |role, definition|
        runtime = definition.dig("spec", "runtime")
        abort "#{role} runtime is missing" unless runtime.is_a?(Hash)
        next unless runtime.key?("volumes")
        abort "#{role} runtime.volumes must be an array" unless runtime["volumes"].is_a?(Array)
      end

      if ARGV.fetch(0) == "disabled"
        %w[config-server shard mongodb].each do |role|
          runtime = definitions.fetch(role).dig("spec", "runtime")
          abort "#{role} must omit runtime.volumes when log collection is disabled" if runtime.key?("volumes")
        end

        mongos_volumes = definitions.fetch("mongos").dig("spec", "runtime", "volumes")
        names = mongos_volumes.map { |volume| volume.fetch("name") }
        abort "mongos must retain only its data volume" unless names == ["data"]
      else
        %w[config-server shard mongodb].each do |role|
          volumes = definitions.fetch(role).dig("spec", "runtime", "volumes")
          names = volumes.map { |volume| volume.fetch("name") }
          abort "#{role} must render the log-data volume" unless names == ["log-data"]
        end

        mongos_volumes = definitions.fetch("mongos").dig("spec", "runtime", "volumes")
        names = mongos_volumes.map { |volume| volume.fetch("name") }
        abort "mongos must render log-data and data volumes" unless names == ["log-data", "data"]
      end

      puts "runtime volumes contract passed for #{ARGV.fetch(0)}"
    ' "$mode"
  }

  It "omits optional volumes instead of rendering null when log collection is disabled"
    When call validate_runtime_volumes disabled
    The status should be success
    The output should include "runtime volumes contract passed for disabled"
  End

  It "renders volume arrays when log collection is enabled"
    When call validate_runtime_volumes enabled
    The status should be success
    The output should include "runtime volumes contract passed for enabled"
  End
End
