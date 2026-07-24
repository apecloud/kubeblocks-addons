# shellcheck shell=bash

Describe "MongoDB static example serviceVersion reference closure"

  validate_example_service_versions() {
    local chart_dir
    local repo_root

    chart_dir=${MONGODB_CHART_DIR:-$(cd .. && pwd)}
    repo_root=$(git -C "$chart_dir" rev-parse --show-toplevel) || return

    helm dependency build "$chart_dir" >/dev/null || return
    helm template kb-addon-mongodb "$chart_dir" | ruby -ryaml -e '
      def selector_matches?(selector, value)
        value == selector || value.start_with?(selector) || Regexp.new(selector).match?(value)
      rescue RegexpError
        false
      end

      def versions_in(text)
        text.scan(/\b\d+\.\d+\.\d+\b/).uniq.sort
      end

      documents = YAML.load_stream($stdin.read).compact
      component_definitions = documents.select { |document| document["kind"] == "ComponentDefinition" }
      component_versions = documents.select { |document| document["kind"] == "ComponentVersion" }
      replica_definitions = component_definitions.select do |definition|
        definition.dig("metadata", "name")&.match?(/^mongodb-/)
      end
      abort "expected one replica ComponentDefinition, got #{replica_definitions.length}" unless replica_definitions.length == 1

      replica_name = replica_definitions.first.dig("metadata", "name")
      supported_versions = component_versions.flat_map do |version|
        release_names = Array(version.dig("spec", "compatibilityRules")).flat_map do |rule|
          next [] unless Array(rule["compDefs"]).any? { |selector| selector_matches?(selector, replica_name) }

          Array(rule["releases"])
        end
        Array(version.dig("spec", "releases")).map do |release|
          release["serviceVersion"] if release_names.include?(release["name"])
        end.compact
      end.uniq.sort
      abort "replica ComponentVersion has no supported serviceVersions" if supported_versions.empty?

      repo_root = ARGV.fetch(0)
      failures = []
      restore_path = File.join(repo_root, "examples", "mongodb", "restore.yaml")
      restore = YAML.load_file(restore_path)
      restore_version = restore.dig("spec", "componentSpecs", 0, "serviceVersion")
      unless supported_versions.include?(restore_version)
        failures << "examples/mongodb/restore.yaml serviceVersion=#{restore_version.inspect} supported=#{supported_versions.join(",")}"
      end

      readmes = {
        "examples/mongodb/README.md" => File.read(File.join(repo_root, "examples", "mongodb", "README.md")),
        "addons/mongodb/README.md" => File.read(File.join(repo_root, "addons", "mongodb", "README.md"))
      }
      readmes.each do |file, readme|
        versions_section = readme[/### Versions\n(.*?)\n## Prerequisites/m, 1].to_s
        actual_versions = versions_in(versions_section)
        unless actual_versions == supported_versions
          failures << "#{file} versions=#{actual_versions.join(",")} supported=#{supported_versions.join(",")}"
        end

        snippet = readme[
          /If you want to create a cluster of specified version.*?The list of supported versions/m,
          0
        ].to_s
        snippet_options = versions_in(snippet[/# Valid options are: \[([^\]]+)\]/, 1].to_s)
        unless snippet_options == supported_versions
          failures << "#{file} snippet_options=#{snippet_options.join(",")} supported=#{supported_versions.join(",")}"
        end

        snippet_selected = snippet[/serviceVersion:\s*"([^"]+)"/, 1]
        unless supported_versions.include?(snippet_selected)
          failures << "#{file} snippet_selected=#{snippet_selected.inspect} unsupported"
        end
      end

      addon_cluster = readmes.fetch("addons/mongodb/README.md")[
        /# cat examples\/mongodb\/cluster\.yaml.*?\n```/m,
        0
      ].to_s
      addon_cluster_options = versions_in(
        addon_cluster[/# Valid options are:?\s*\[([^\]]+)\](?=\n\s+serviceVersion:)/, 1].to_s
      )
      unless addon_cluster_options == supported_versions
        failures << "addons/mongodb/README.md embedded_cluster_options=#{addon_cluster_options.join(",")} supported=#{supported_versions.join(",")}"
      end

      addon_restore = readmes.fetch("addons/mongodb/README.md")[
        /# cat examples\/mongodb\/restore\.yaml.*?\n```/m,
        0
      ].to_s
      addon_restore_version = addon_restore[/serviceVersion:\s*"([^"]+)"/, 1]
      unless supported_versions.include?(addon_restore_version)
        failures << "addons/mongodb/README.md embedded_restore_version=#{addon_restore_version.inspect} unsupported"
      end
      unless addon_restore_version == restore_version
        failures << "addons/mongodb/README.md embedded_restore_version=#{addon_restore_version.inspect} canonical_restore_version=#{restore_version.inspect} mismatch"
      end

      cluster_source = File.read(File.join(repo_root, "examples", "mongodb", "cluster.yaml"))
      cluster_options = versions_in(
        cluster_source[/# Valid options are:?\s*\[([^\]]+)\](?=\n\s+serviceVersion:)/, 1].to_s
      )
      unless cluster_options == supported_versions
        failures << "examples/mongodb/cluster.yaml comment_options=#{cluster_options.join(",")} supported=#{supported_versions.join(",")}"
      end

      unless failures.empty?
        failures.each { |failure| warn failure }
        abort "static example serviceVersion reference closure failed: #{failures.length} drift(s)"
      end

      puts "static example serviceVersion reference closure passed for #{supported_versions.length} releases"
    ' "$repo_root"
  }

  It "keeps YAML examples and both README surfaces aligned with rendered ComponentVersion releases"
    When call validate_example_service_versions
    The status should be success
    The output should include "static example serviceVersion reference closure passed for 6 releases"
  End
End
