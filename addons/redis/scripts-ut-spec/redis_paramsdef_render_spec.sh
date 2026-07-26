# shellcheck shell=bash

Describe "Redis ParametersDefinition render contract"
  render_external_managed_bindings() {
    helm template redis .. | ruby -ryaml -e '
      documents = YAML.load_stream(ARGF.read).compact
      component_definitions = documents.select do |document|
        document["kind"] == "ComponentDefinition"
      end
      parameter_definitions = documents.select do |document|
        document["kind"] == "ParametersDefinition"
      end

      external_configs = component_definitions.flat_map do |component_definition|
        Array(component_definition.dig("spec", "configs")).map do |config|
          next unless config["externalManaged"] == true
          [component_definition.dig("metadata", "name"), config["name"]]
        end.compact
      end

      bindings = external_configs.map do |component_definition, template_name|
        matches = parameter_definitions.select do |parameter_definition|
          pattern = parameter_definition.dig("spec", "componentDef")
          pattern &&
            Regexp.new(pattern).match?(component_definition) &&
            parameter_definition.dig("spec", "templateName") == template_name
        end
        abort "#{component_definition}/#{template_name}: expected exactly one matching ParametersDefinition, got #{matches.length}" unless matches.length == 1
        "#{component_definition}/#{template_name}=#{matches.first.dig("metadata", "name")}"
      end

      puts "external_configs=#{external_configs.length}"
      puts "matched_bindings=#{bindings.length}"
      puts bindings.sort
    '
  }

  It "binds every external-managed config to exactly one ParametersDefinition"
    When call render_external_managed_bindings
    The status should be success
    The first line of output should eq "external_configs=12"
    The second line of output should eq "matched_bindings=12"
  End

  render_upgrade_bindings() {
    workdir=$(mktemp -d)
    cp -R .. "$workdir/next"
    ruby -ryaml -e '
      path = ARGV.fetch(0)
      chart = YAML.load_file(path)
      chart["version"] = "1.2.0-alpha.1"
      File.write(path, chart.to_yaml)
    ' "$workdir/next/Chart.yaml"

    helm template redis .. >"$workdir/current.yaml"
    helm template redis "$workdir/next" >"$workdir/next.yaml"

    ruby -ryaml -e '
      documents = ARGV.flat_map { |path| YAML.load_stream(File.read(path)).compact }
      component_definitions = documents.select { |document| document["kind"] == "ComponentDefinition" }
      parameter_definitions = documents.select { |document| document["kind"] == "ParametersDefinition" }
      config_maps = documents.select { |document| document["kind"] == "ConfigMap" }

      names = parameter_definitions.map { |definition| definition.dig("metadata", "name") }
      abort "ParametersDefinition metadata names collide across upgrades" unless names.length == names.uniq.length

      external_configs = component_definitions.flat_map do |component_definition|
        Array(component_definition.dig("spec", "configs")).map do |config|
          next unless config["externalManaged"] == true
          [component_definition, config]
        end.compact
      end

      matched = 0
      files = 0
      kept = 0
      external_configs.each do |component_definition, config|
        component_name = component_definition.dig("metadata", "name")
        matches = parameter_definitions.select do |parameter_definition|
          pattern = parameter_definition.dig("spec", "componentDef")
          pattern &&
            Regexp.new(pattern).match?(component_name) &&
            parameter_definition.dig("spec", "templateName") == config["name"]
        end
        abort "#{component_name}/#{config["name"]}: expected exactly one retained ParametersDefinition, got #{matches.length}" unless matches.length == 1
        matched += 1

        parameter_definition = matches.first
        kept += 1 if parameter_definition.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"

        template = config_maps.find do |config_map|
          config_map.dig("metadata", "name") == config["template"] &&
            (config_map.dig("metadata", "namespace") || "default") == config["namespace"]
        end
        file_name = parameter_definition.dig("spec", "fileName")
        abort "#{component_name}/#{config["name"]}: #{file_name} missing from #{config["template"]}" unless template && template.fetch("data", {}).key?(file_name)
        files += 1
      end

      puts "pd_names=#{names.length} unique=#{names.uniq.length}"
      puts "external_configs=#{external_configs.length}"
      puts "matched_bindings=#{matched}"
      puts "file_bindings=#{files}"
      puts "kept_bindings=#{kept}"
    ' "$workdir/current.yaml" "$workdir/next.yaml"
    status=$?
    rm -rf "$workdir"
    return "$status"
  }

  It "keeps unique old and new PD identities covered across chart upgrades"
    When call render_upgrade_bindings
    The status should be success
    The output should eq "pd_names=24 unique=24
external_configs=24
matched_bindings=24
file_bindings=24
kept_bindings=24"
  End
End
