# shellcheck shell=bash

Describe "ApeCloud MySQL ComponentDefinition runtime render contract"

  validate_runtime_contract() {
    local mode="$1"
    local chart_dir
    local -a helm_args

    chart_dir=$(cd .. && pwd)
    helm dependency build "$chart_dir" >/dev/null || return 1
    helm_args=(template kb-addon-apecloud-mysql "$chart_dir")
    case "$mode" in
      enabled)
        helm_args+=(--set logCollector.enabled=true)
        ;;
      sensitive)
        helm_args+=(
          --set-string cluster.templateConfig=true
          --set-string cluster.customConfig=123
          --set-string cluster.dynamicConfig=alpha:beta
        )
        ;;
    esac

    helm "${helm_args[@]}" | ruby -ryaml -e '
      mode = ARGV.fetch(0)
      documents = YAML.load_stream($stdin.read).compact
      matches = documents.select do |doc|
        doc["kind"] == "ComponentDefinition" &&
          doc.dig("metadata", "name")&.match?(/^apecloud-mysql-/)
      end
      abort "expected one ApeCloud MySQL ComponentDefinition, got #{matches.length}" unless matches.length == 1

      runtime = matches.first.dig("spec", "runtime")
      abort "runtime is missing" unless runtime.is_a?(Hash)
      containers = runtime.fetch("containers")

      find_container = lambda do |name|
        found = containers.select { |container| container["name"] == name }
        abort "expected one #{name} container, got #{found.length}" unless found.length == 1
        found.first
      end

      env_value = lambda do |container, name|
        found = container.fetch("env").select { |entry| entry["name"] == name }
        abort "expected one #{name} env entry, got #{found.length}" unless found.length == 1
        entry = found.first
        abort "#{name} must contain a value key" unless entry.key?("value")
        value = entry["value"]
        abort "#{name} value must be a string, got #{value.class}" unless value.is_a?(String)
        value
      end

      mysql = find_container.call("mysql")
      expected = if mode == "sensitive"
                   {
                     "MYSQL_TEMPLATE_CONFIG" => "true",
                     "MYSQL_CUSTOM_CONFIG" => "123",
                     "MYSQL_DYNAMIC_CONFIG" => "alpha:beta"
                   }
                 else
                   {
                     "MYSQL_TEMPLATE_CONFIG" => "",
                     "MYSQL_CUSTOM_CONFIG" => "",
                     "MYSQL_DYNAMIC_CONFIG" => ""
                   }
                 end

      expected.each do |name, value|
        actual = env_value.call(mysql, name)
        abort "#{name} expected #{value.inspect}, got #{actual.inspect}" unless actual == value
      end

      vtablet = find_container.call("vtablet")
      grpc_port = env_value.call(vtablet, "VTTABLET_GRPC_PORT")
      abort "VTTABLET_GRPC_PORT expected \"16100\", got #{grpc_port.inspect}" unless grpc_port == "16100"

      if mode == "enabled"
        volumes = runtime["volumes"]
        abort "runtime.volumes must be an array" unless volumes.is_a?(Array)
        names = volumes.map { |volume| volume.fetch("name") }
        abort "runtime.volumes expected [\"log-data\"], got #{names.inspect}" unless names == ["log-data"]
      else
        abort "runtime must omit volumes when log collection is disabled" if runtime.key?("volumes")
      end

      puts "runtime render contract passed for #{mode}"
    ' "$mode"
  }

  It "renders API-valid string env values and omits disabled volumes"
    When call validate_runtime_contract default
    The status should be success
    The output should include "runtime render contract passed for default"
  End

  It "renders the log volume as an array when log collection is enabled"
    When call validate_runtime_contract enabled
    The status should be success
    The output should include "runtime render contract passed for enabled"
  End

  It "preserves YAML-sensitive config values as strings"
    When call validate_runtime_contract sensitive
    The status should be success
    The output should include "runtime render contract passed for sensitive"
  End
End
