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
End
