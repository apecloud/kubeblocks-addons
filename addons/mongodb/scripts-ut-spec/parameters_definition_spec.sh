# shellcheck shell=bash

Describe "MongoDB ParametersDefinition ownership contract"

  prepare_chart() {
    local chart_dir
    chart_dir=${MONGODB_CHART_DIR:-$(cd .. && pwd)}
    helm dependency build "$chart_dir" >/dev/null
  }

  render_and_validate_parameters_definitions() {
    local chart_dir mutant render_dir status

    chart_dir=${MONGODB_CHART_DIR:-$(cd .. && pwd)}
    mutant=${1:-}
    render_dir=$(mktemp -d)

    helm template kb-addon-mongodb "$chart_dir" > "$render_dir/default.yaml" &&
      helm template kb-addon-mongodb "$chart_dir" \
        --set resourceNamePrefix=static-resource > "$render_dir/resource-prefix.yaml" &&
      helm template kb-addon-mongodb "$chart_dir" \
        --set cmpdVersionPrefix=static-cmpd > "$render_dir/cmpd-prefix.yaml" &&
      helm template kb-addon-mongodb "$chart_dir" \
        --set resourceNamePrefix=static-resource \
        --set cmpdVersionPrefix=static-cmpd > "$render_dir/both-prefixes.yaml" &&
      ruby -ryaml -e '
        mutant, *paths = ARGV
        paths.each do |path|
          documents = YAML.load_stream(File.read(path)).compact
          definitions = documents.select { |doc| doc["kind"] == "ParametersDefinition" }

          case mutant
          when "fixed-name"
            definitions[0]["metadata"]["name"] = "mongodb-config-pd-fixed"
            definitions[1]["metadata"]["name"] = "mongos-config-pd-fixed"
          when "swapped-name"
            definitions[0]["metadata"]["name"], definitions[1]["metadata"]["name"] =
              definitions[1]["metadata"]["name"], definitions[0]["metadata"]["name"]
          when "every-dot"
            definitions.each do |definition|
              definition["spec"]["componentDef"] =
                definition.dig("spec", "componentDef").gsub("\\.", ".")
            end
          when ""
            next
          else
            abort "unknown mutant: #{mutant}"
          end

          File.write(path, documents.map { |doc| YAML.dump(doc) }.join)
        end
      ' "$mutant" "$render_dir/default.yaml" "$render_dir/resource-prefix.yaml" \
        "$render_dir/cmpd-prefix.yaml" "$render_dir/both-prefixes.yaml" &&
      ruby -ryaml -e '
        paths = ARGV
        retained_names = %w[
          mongodb-config-pd-1.2.0-alpha.0
          mongos-config-pd-1.2.0-alpha.0
        ].freeze
        default_selectors = {
          "mongodb-config-pd-1.2.0-alpha.0" =>
            "^(mongodb-1\\.2\\.0-alpha\\.0|mongo-shard-1\\.2\\.0-alpha\\.0|mongo-config-server-1\\.2\\.0-alpha\\.0)$",
          "mongos-config-pd-1.2.0-alpha.0" =>
            "^mongo-mongos-1\\.2\\.0-alpha\\.0$"
        }.freeze
        prefixed_selectors = {
          "mongodb-config-pd-1.2.0-alpha.0" =>
            "^(static-cmpd-1\\.2\\.0-alpha\\.0|mongo-shard-static-cmpd-1\\.2\\.0-alpha\\.0|mongo-config-server-static-cmpd-1\\.2\\.0-alpha\\.0)$",
          "mongos-config-pd-1.2.0-alpha.0" =>
            "^mongo-mongos-static-cmpd-1\\.2\\.0-alpha\\.0$"
        }.freeze
        expected_selectors = {
          "default.yaml" => default_selectors,
          "resource-prefix.yaml" => default_selectors,
          "cmpd-prefix.yaml" => prefixed_selectors,
          "both-prefixes.yaml" => prefixed_selectors
        }.freeze

        paths.each do |path|
          documents = YAML.load_stream(File.read(path)).compact
          definitions = documents.select { |doc| doc["kind"] == "ComponentDefinition" }
          parameter_definitions = documents.select { |doc| doc["kind"] == "ParametersDefinition" }

          abort "#{path}: expected two ParametersDefinitions" unless parameter_definitions.length == 2
          names = parameter_definitions.map { |definition| definition.dig("metadata", "name") }.sort
          abort "#{path}: retained literal ParametersDefinition names changed" unless names == retained_names

          owners = definitions.select do |definition|
            Array(definition.dig("spec", "configs")).any? do |config|
              config["name"] == "mongodb-config" && config["externalManaged"] == true
            end
          end
          abort "#{path}: expected four externally managed mongodb-config owners" unless owners.length == 4

          by_name = parameter_definitions.to_h do |definition|
            [definition.dig("metadata", "name"), definition]
          end
          expected_for_render = expected_selectors.fetch(File.basename(path))
          expected_for_render.each do |name, expected_selector|
            selector = by_name.fetch(name).dig("spec", "componentDef")
            matcher = Regexp.new(selector)
            expected_selector.scan(/[A-Za-z0-9-]+(?:\\\.[A-Za-z0-9-]+)+/).each do |escaped_owner|
              owner = escaped_owner.gsub("\\.", ".")
              owner.each_char.with_index.select { |char, _index| char == "." }.each do |_char, index|
                near_collision = owner.dup
                near_collision[index] = "x"
                if matcher.match?(near_collision)
                  abort "#{path}: #{name} regex also matches near-collision #{near_collision}"
                end
              end
            end
            unless selector == expected_selector
              abort "#{path}: retained name-to-selector mapping changed for #{name}"
            end
          end

          matchers = parameter_definitions.map do |definition|
            Regexp.new(definition.dig("spec", "componentDef"))
          end
          owners.each do |owner|
            name = owner.dig("metadata", "name")
            matching = matchers.count { |matcher| matcher.match?(name) }
            abort "#{path}: #{name} is covered #{matching} times" unless matching == 1
          end
        end

        puts "ParametersDefinition ownership contract passed for #{paths.length} renders"
      ' "$render_dir/default.yaml" "$render_dir/resource-prefix.yaml" \
        "$render_dir/cmpd-prefix.yaml" "$render_dir/both-prefixes.yaml"
    status=$?

    rm -rf "$render_dir"
    return "$status"
  }

  BeforeAll "prepare_chart"

  It "quotes component names while preserving retained object identities"
    When call render_and_validate_parameters_definitions
    The status should be success
    The output should include "ParametersDefinition ownership contract passed for 4 renders"
  End

  It "rejects arbitrary fixed object names"
    When call render_and_validate_parameters_definitions fixed-name
    The status should be failure
    The stderr should include "retained literal ParametersDefinition names changed"
  End

  It "rejects swapping retained object names across selectors"
    When call render_and_validate_parameters_definitions swapped-name
    The status should be failure
    The stderr should include "retained name-to-selector mapping changed"
  End

  It "rejects unquoting every literal dot in the selectors"
    When call render_and_validate_parameters_definitions every-dot
    The status should be failure
    The stderr should include "regex also matches near-collision"
  End
End
