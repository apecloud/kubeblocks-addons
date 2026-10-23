# shellcheck shell=bash

Describe "MongoDB backup snapshot volume contract"

  render_and_validate_snapshot_volumes() {
    local chart_dir render_dir status

    chart_dir=${MONGODB_CHART_DIR:-$(cd .. && pwd)}
    render_dir=$(mktemp -d)

    helm dependency build "$chart_dir" >/dev/null || return
    # shellcheck disable=SC2016
    helm template kb-addon-mongodb "$chart_dir" \
      --set cmpdVersionPrefix=static-cmpd > "$render_dir/cmpd-prefix.yaml" &&
      helm template kb-addon-mongodb "$chart_dir" \
        --set resourceNamePrefix=static-resource \
        --set cmpdVersionPrefix=static-cmpd > "$render_dir/both-prefixes.yaml" &&
      helm template kb-addon-mongodb "$chart_dir" > "$render_dir/default.yaml" &&
      helm template kb-addon-mongodb "$chart_dir" \
        --set resourceNamePrefix=static-resource > "$render_dir/resource-prefix.yaml" &&
      ruby -ryaml -e '
      def compdef_match?(name, pattern)
        return true if name.start_with?(pattern)
        return false unless pattern.match?(/[\\.+*?()|\[\]{}^$]/)

        Regexp.new(pattern).match?(name)
      rescue RegexpError
        false
      end

      total_snapshot_methods = 0
      total_snapshot_volumes = 0
      expected_snapshot_targets = {
        "cmpd-prefix.yaml" => "static-cmpd-1.2.0-alpha.0/data",
        "both-prefixes.yaml" => "static-cmpd-1.2.0-alpha.0/data",
        "default.yaml" => "mongodb-1.2.0-alpha.0/data",
        "resource-prefix.yaml" => "mongodb-1.2.0-alpha.0/data"
      }

      ARGV.each do |path|
        expected_snapshot_target = expected_snapshot_targets.fetch(File.basename(path))
        documents = YAML.load_stream(File.read(path)).compact
        definitions = documents.select { |doc| doc["kind"] == "ComponentDefinition" }
        policies = documents.select { |doc| doc["kind"] == "BackupPolicyTemplate" }
        snapshot_methods = 0
        snapshot_volumes = 0
        snapshot_targets = []

        policies.each do |policy|
          patterns = Array(policy.dig("spec", "compDefs"))
          matches = definitions.select do |definition|
            name = definition.dig("metadata", "name")
            patterns.any? { |pattern| compdef_match?(name, pattern) }
          end
          abort "#{path}: #{policy.dig("metadata", "name")} must resolve exactly one ComponentDefinition, got #{matches.length}" unless matches.length == 1

          declared = Array(matches.first.dig("spec", "volumes")).to_h do |volume|
            [volume.fetch("name"), volume["needSnapshot"] == true]
          end

          Array(policy.dig("spec", "backupMethods")).each do |method|
            next unless method["snapshotVolumes"] == true

            snapshot_methods += 1
            names = Array(method.dig("targetVolumes", "volumes"))
            abort "#{path}: #{method["name"]} snapshot method has no target volume" if names.empty?
            names.each do |name|
              snapshot_volumes += 1
              abort "#{path}: #{method["name"]} target volume #{name.inspect} is not declared needSnapshot=true in #{matches.first.dig("metadata", "name")}" unless declared[name]
              snapshot_targets << "#{matches.first.dig("metadata", "name")}/#{name}"
            end
          end
        end

        snapshot_declarations = definitions.flat_map do |definition|
          Array(definition.dig("spec", "volumes")).each_with_object([]) do |volume, declarations|
            if volume["needSnapshot"] == true
              declarations << "#{definition.dig("metadata", "name")}/#{volume.fetch("name")}"
            end
          end
        end

        abort "#{path}: expected one snapshot method, got #{snapshot_methods}" unless snapshot_methods == 1
        abort "#{path}: expected one snapshot target volume, got #{snapshot_volumes}" unless snapshot_volumes == 1
        abort "#{path}: snapshot target/declaration mismatch targets=#{snapshot_targets.sort.inspect} declarations=#{snapshot_declarations.sort.inspect}" unless snapshot_targets.sort == snapshot_declarations.sort
        abort "#{path}: expected snapshot target/declaration #{expected_snapshot_target.inspect}, got targets=#{snapshot_targets.sort.inspect} declarations=#{snapshot_declarations.sort.inspect}" unless snapshot_targets.sort == [expected_snapshot_target] && snapshot_declarations.sort == [expected_snapshot_target]

        total_snapshot_methods += snapshot_methods
        total_snapshot_volumes += snapshot_volumes
      end

      puts "snapshot volume contract passed for #{ARGV.length} renders, #{total_snapshot_methods} methods and #{total_snapshot_volumes} target volumes"
    ' "$render_dir/cmpd-prefix.yaml" "$render_dir/both-prefixes.yaml" \
      "$render_dir/default.yaml" "$render_dir/resource-prefix.yaml"
    status=$?

    rm -rf "$render_dir"
    return "$status"
  }

  It "declares every CSI snapshot target volume in the matching ComponentDefinition"
    When call render_and_validate_snapshot_volumes
    The status should be success
    The output should include "snapshot volume contract passed for 4 renders, 4 methods and 4 target volumes"
  End
End
