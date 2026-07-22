# shellcheck shell=bash

Describe "MongoDB backup version mapping contract"

  render_and_validate_backup_version_mappings() {
    local chart_dir

    chart_dir=${MONGODB_CHART_DIR:-$(cd .. && pwd)}
    helm template kb-addon-mongodb "$chart_dir" --dependency-update | ruby -ryaml -e '
      def mapping_for(method, env_name)
        env = Array(method["env"]).find { |item| item["name"] == env_name }
        env&.dig("valueFrom", "versionMapping") || []
      end

      def resolve(mapping, service_version)
        exact = mapping.find do |entry|
          Array(entry["serviceVersions"]).include?(service_version)
        end
        return exact["mappedValue"] if exact

        prefix = mapping.find do |entry|
          Array(entry["serviceVersions"]).any? do |version|
            service_version.start_with?(version)
          end
        end
        prefix&.fetch("mappedValue", nil)
      end

      values = YAML.load_file(ARGV.fetch(0))
      active = values.fetch("versions").flat_map do |group|
        group.fetch("minors").reject { |minor| minor[4] }.map do |minor|
          {
            "serviceVersion" => minor[1],
            "mongodbTag" => minor[2],
            "pbmTag" => minor[3]
          }
        end
      end

      documents = YAML.load_stream($stdin.read).compact
      policies = documents.select { |doc| doc["kind"] == "BackupPolicyTemplate" }
      replica = policies.find { |doc| doc.dig("metadata", "name") == "mongodb-backup-policy-template" }
      shard = policies.find { |doc| doc.dig("metadata", "name") == "mongodb-shard-backup-policy-template" }
      abort "replica BackupPolicyTemplate is missing" unless replica
      abort "shard BackupPolicyTemplate is missing" unless shard

      replica_methods = replica.dig("spec", "backupMethods").to_h { |method| [method["name"], method] }
      shard_methods = shard.dig("spec", "backupMethods").to_h { |method| [method["name"], method] }

      active.each do |release|
        service_version = release.fetch("serviceVersion")
        actual = resolve(mapping_for(replica_methods.fetch("dump"), "IMAGE_TAG"), service_version)
        expected = release.fetch("mongodbTag")
        abort "replica dump #{service_version} IMAGE_TAG=#{actual.inspect}, expected #{expected.inspect}" unless actual == expected

        %w[pbm-physical pbm-pitr].each do |method_name|
          actual = resolve(mapping_for(replica_methods.fetch(method_name), "PBM_IMAGE_TAG"), service_version)
          expected = release.fetch("pbmTag")
          abort "replica #{method_name} #{service_version} PBM_IMAGE_TAG=#{actual.inspect}, expected #{expected.inspect}" unless actual == expected
        end

        %w[dump pbm-physical pbm-pitr].each do |method_name|
          method = shard_methods.fetch(method_name)
          actual_mongodb = resolve(mapping_for(method, "PSM_IMAGE_TAG"), service_version)
          expected_mongodb = release.fetch("mongodbTag")
          abort "shard #{method_name} #{service_version} PSM_IMAGE_TAG=#{actual_mongodb.inspect}, expected #{expected_mongodb.inspect}" unless actual_mongodb == expected_mongodb

          actual_pbm = resolve(mapping_for(method, "PBM_IMAGE_TAG"), service_version)
          expected_pbm = release.fetch("pbmTag")
          abort "shard #{method_name} #{service_version} PBM_IMAGE_TAG=#{actual_pbm.inspect}, expected #{expected_pbm.inspect}" unless actual_pbm == expected_pbm
        end
      end

      puts "backup version mapping contract passed for #{active.length} active releases"
    ' "$chart_dir/values.yaml"
  }

  It "maps every active release to the declared MongoDB and PBM image tags"
    When call render_and_validate_backup_version_mappings
    The status should be success
    The output should include "backup version mapping contract passed for 6 active releases"
  End
End
