# shellcheck shell=bash

Describe "MongoDB syncer image contract"

  render_and_validate_syncer_image() {
    local chart_dir

    chart_dir=$(cd .. && pwd)
    # shellcheck disable=SC2016 # Ruby owns interpolation inside this program.
    helm template kb-addon-mongodb "$chart_dir" --dependency-update | ruby -ryaml -e '
      expected = "docker.io/apecloud/syncer:0.7.7"
      documents = YAML.load_stream($stdin.read).compact

      component_versions = documents.select { |doc| doc["kind"] == "ComponentVersion" }
      versions = component_versions.select do |doc|
        %w[mongodb mongodb-shard].include?(doc.dig("metadata", "name"))
      end
      abort "expected mongodb and mongodb-shard ComponentVersions" unless versions.length == 2

      versions.each do |version|
        releases = version.dig("spec", "releases")
        abort "#{version.dig("metadata", "name")} releases are missing" unless releases.is_a?(Array) && !releases.empty?
        releases.each do |release|
          actual = release.dig("images", "init-syncer")
          abort "#{version.dig("metadata", "name")} #{release["name"]} init-syncer=#{actual.inspect}, expected #{expected}" unless actual == expected
        end
      end

      definitions = documents.select { |doc| doc["kind"] == "ComponentDefinition" }
      direct_images = definitions.flat_map do |definition|
        Array(definition.dig("spec", "runtime", "initContainers")).map do |container|
          container["image"] if container["name"] == "init-syncer" && container.key?("image")
        end.compact
      end
      abort "expected two direct init-syncer images, got #{direct_images.length}" unless direct_images.length == 2
      abort "direct init-syncer image mismatch: #{direct_images.inspect}" unless direct_images.all? { |image| image == expected }

      rendered = documents.to_s
      abort "stale syncer 0.6.7 remains in rendered resources" if rendered.include?("apecloud/syncer:0.6.7")

      puts "syncer image contract passed: #{expected}"
    '
  }

  It "pins every MongoDB init-syncer mapping to 0.7.7"
    When call render_and_validate_syncer_image
    The status should be success
    The output should include "syncer image contract passed: docker.io/apecloud/syncer:0.7.7"
  End
End
