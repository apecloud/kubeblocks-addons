# shellcheck shell=bash

Describe "MongoDB ParametersDefinition ownership contract"

  render_and_validate_parameters_definitions() {
    local chart_dir render_dir status

    chart_dir=${MONGODB_CHART_DIR:-$(cd .. && pwd)}
    render_dir=$(mktemp -d)

    helm template kb-addon-mongodb "$chart_dir" --dependency-update > "$render_dir/default.yaml" &&
      helm template kb-addon-mongodb "$chart_dir" --dependency-update \
        --set resourceNamePrefix=static-resource > "$render_dir/resource-prefix.yaml" &&
      helm template kb-addon-mongodb "$chart_dir" --dependency-update \
        --set cmpdVersionPrefix=static-cmpd > "$render_dir/cmpd-prefix.yaml" &&
      helm template kb-addon-mongodb "$chart_dir" --dependency-update \
        --set resourceNamePrefix=static-resource \
        --set cmpdVersionPrefix=static-cmpd > "$render_dir/both-prefixes.yaml" &&
      ruby -ryaml -e '
        paths = ARGV
        all_names = []

        paths.each do |path|
          documents = YAML.load_stream(File.read(path)).compact
          definitions = documents.select { |doc| doc["kind"] == "ComponentDefinition" }
          parameter_definitions = documents.select { |doc| doc["kind"] == "ParametersDefinition" }

          abort "#{path}: expected two ParametersDefinitions" unless parameter_definitions.length == 2

          owners = definitions.select do |definition|
            Array(definition.dig("spec", "configs")).any? do |config|
              config["name"] == "mongodb-config" && config["externalManaged"] == true
            end
          end
          abort "#{path}: expected four externally managed mongodb-config owners" unless owners.length == 4

          matchers = parameter_definitions.map do |definition|
            Regexp.new(definition.dig("spec", "componentDef"))
          end

          owners.each do |owner|
            name = owner.dig("metadata", "name")
            matching = matchers.count { |matcher| matcher.match?(name) }
            abort "#{path}: #{name} is covered #{matching} times" unless matching == 1

            near_collision = name.sub(".", "x")
            next if near_collision == name
            abort "#{path}: regex also matches near-collision #{near_collision}" if matchers.any? { |matcher| matcher.match?(near_collision) }
          end

          all_names.concat(parameter_definitions.map { |definition| definition.dig("metadata", "name") })
        end

        abort "ParametersDefinition names collide across prefix renders" unless all_names.uniq.length == all_names.length
        puts "ParametersDefinition ownership contract passed for #{paths.length} renders"
      ' "$render_dir/default.yaml" "$render_dir/resource-prefix.yaml" \
        "$render_dir/cmpd-prefix.yaml" "$render_dir/both-prefixes.yaml"
    status=$?

    rm -rf "$render_dir"
    return "$status"
  }

  It "quotes component names and isolates cluster-scoped names across prefix dimensions"
    When call render_and_validate_parameters_definitions
    The status should be success
    The output should include "ParametersDefinition ownership contract passed for 4 renders"
  End
End
